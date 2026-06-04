// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../model/call_system_project.dart';
import '../model/call_flow.dart';
import '../model/call_node.dart';
import '../model/pbx_entities.dart';
import 'call_system_exporter.dart';

/// Exports the portable [CallSystemProject] to a **Telnyx Call Control** state
/// machine descriptor.
///
/// WHY A STATE MACHINE (and not declarative markup):
/// Telnyx Call Control is *imperative and event-driven*. Unlike Twilio's TwiML
/// (a declarative document the platform walks top-to-bottom), Telnyx hands your
/// webhook a stream of events (`call.answered`, `call.speak.ended`,
/// `call.gather.ended`, `call.dtmf.received`, `call.hangup`, ...) and you reply
/// by POSTing *commands* (`speak`, `gather_using_speak`, `dial`, `transfer`,
/// `hangup`, ...) back to the Call Control API. There is no file Telnyx
/// "runs" — the logic lives in YOUR webhook handler.
///
/// So the only faithful artifact is a **per-node command + transition table**
/// that a thin webhook dispatcher can execute: arrive in a state → issue its
/// Call Control command(s) → when the relevant completion event fires, follow
/// the matching port to the next state. That is exactly the shape this exporter
/// emits:
///
/// ```
///   {
///     "telnyx": { ...meta... },
///     "flows": [
///       {
///         "id": ..., "name": ..., "entry": "nodeId",
///         "states": [
///           { "nodeId", "type", "label",
///             "command": { "command": "speak", "payload": {...} } | null,
///             "commands": [ ...optional extra commands... ],
///             "transitions": { "port": "targetNodeId|null" },
///             "events": { "telnyx_event": "port" },   // event to port hint
///             "notes": [ ... ] }
///         ]
///       }
///     ]
///   }
/// ```
///
/// Each exporter only maps what the backend can express; anything Telnyx Call
/// Control can't model natively (true ACD queues, dial-by-name directory,
/// schedule evaluation) is emitted with an explanatory `command: null` +
/// inline `notes`, and surfaced again through [notes].
class TelnyxExporter implements CallSystemExporter {
  const TelnyxExporter();

  @override
  String get providerKey => 'telnyx';

  @override
  String get displayName => 'Telnyx (Call Control)';

  @override
  String get artifactExtension => 'json';

  // ── Public API ──────────────────────────────────────────────────────────

  @override
  Map<String, String> export(CallSystemProject project) {
    final flows = <Map<String, dynamic>>[];
    for (final flow in project.flows) {
      flows.add(_exportFlow(project, flow));
    }

    final root = <String, dynamic>{
      'telnyx': {
        // Tells the webhook dispatcher this is a Call Control descriptor.
        'integration': 'call_control',
        'descriptorVersion': 1,
        'project': project.name,
        'subCategory': project.subCategory.name,
        'experienceMode': project.experienceMode,
        'isOutbound': project.isOutbound,
        // DIDs map a Telnyx number → the flow its inbound webhook should start.
        // (You bind these to a Call Control Application / number in the portal.)
        'inboundRoutes': [
          for (final did in project.dids)
            {
              'e164': did.e164,
              if (did.label != null) 'label': did.label,
              'flowId': did.flowId,
              'managed': did.managed,
            },
        ],
        // Carried verbatim so the webhook can interpolate ${var} into speak text.
        'variables': project.variables,
      },
      'flows': flows,
    };

    return {
      'telnyx_call_control.json': const JsonEncoder.withIndent(
        '  ',
      ).convert(root),
    };
  }

  @override
  List<String> notes(CallSystemProject project) {
    final out = <String>[
      'Telnyx Call Control is an imperative, event-driven webhook API: there is '
          'no document Telnyx executes. This file is a per-node command + '
          'transition table that your Call Control webhook dispatcher runs — on '
          'each completion event (call.speak.ended, call.gather.ended, '
          'call.dtmf.received, call.dial.answered, call.hangup, ...) follow the '
          "matching port to the next state and POST that state's command.",
      'Bind each inbound number under "telnyx.inboundRoutes" to a Telnyx Call '
          'Control Application; its webhook starts the referenced flow on '
          'call.initiated/answered.',
      'TTS prompts are emitted as the "speak" command (Telnyx natural TTS). '
          'Recorded audio assets (Prompt.audioAssetPath) are emitted as the '
          '"playback_start" command pointing at audio_url — host those assets '
          'and rewrite the placeholder URL.',
    ];

    // Surface capability gaps that actually appear in this project.
    final hasQueue = project.flows.any(
      (f) => f.nodes.any((n) => n.type == CallNodeType.queue),
    );
    final hasDirectory = project.flows.any(
      (f) => f.nodes.any((n) => n.type == CallNodeType.playDirectory),
    );
    final hasSchedule = project.flows.any(
      (f) => f.nodes.any((n) => n.type == CallNodeType.schedule),
    );
    final hasRingGroup = project.flows.any(
      (f) => f.nodes.any((n) => n.type == CallNodeType.ringGroup),
    );
    final hasVoicebot = project.flows.any(
      (f) => f.nodes.any((n) => n.type == CallNodeType.aiVoicebot),
    );
    final hasSubFlow = project.flows.any(
      (f) => f.nodes.any((n) => n.type == CallNodeType.subFlow),
    );

    if (hasQueue) {
      out.add(
        'ACD queues are not a native Call Control primitive. Queue states are '
        'emitted as the "enqueue" command (Telnyx call queues) with agent '
        'extensions listed; ring-strategy/music-on-hold are advisory and must '
        'be implemented in your dequeue/agent-dial logic.',
      );
    }
    if (hasRingGroup) {
      out.add(
        'Ring groups are modeled by simultaneously dialing members. Only '
        'ring-all maps cleanly to a single "dial"; hunt/round-robin strategies '
        'require your webhook to dial members sequentially (the strategy is '
        'recorded in the state for that logic).',
      );
    }
    if (hasSchedule) {
      out.add(
        'Time-of-day/holiday evaluation has no Call Control command. Schedule '
        'states carry the referenced TimeCondition; your webhook must evaluate '
        'open/closed/holiday and pick the matching transition.',
      );
    }
    if (hasDirectory) {
      out.add(
        'Dial-by-name directory has no native command. Directory states are '
        'emitted as a gather_using_speak shell; matching a spoken/typed name '
        'to an extension must be handled in your webhook.',
      );
    }
    if (hasVoicebot) {
      out.add(
        'aiVoicebot states emit a "streaming_start" command to bridge call '
        'media to your Omni voicebot via Telnyx media streaming '
        '(WebSocket/bidirectional). The transfer/hangup/next ports are driven '
        'by control messages your voicebot sends back.',
      );
    }
    if (hasSubFlow) {
      out.add(
        'subFlow states are a dispatcher convention (push/pop the target '
        'flow), not a Telnyx command. The "returned" port resumes after the '
        'sub-flow completes.',
      );
    }
    return out;
  }

  // ── Flow + node mapping ─────────────────────────────────────────────────

  /// Walks a flow from its [CallFlow.entryNode] following `outputs`, emitting one
  /// state object per reachable node. Unreachable nodes are still emitted (so the
  /// table is complete) but flagged in their notes.
  Map<String, dynamic> _exportFlow(CallSystemProject project, CallFlow flow) {
    final states = <Map<String, dynamic>>[];

    // Reachability walk from the entry node (BFS over outputs).
    final reachable = <String>{};
    final entry = flow.entryNode;
    if (entry != null) {
      final stack = <String>[entry.id];
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        if (!reachable.add(id)) continue;
        final node = flow.nodeById(id);
        if (node == null) continue;
        for (final target in node.outputs.values) {
          if (target != null && !reachable.contains(target)) {
            stack.add(target);
          }
        }
      }
    }

    // Emit reachable nodes first (entry first), then any orphans.
    final ordered = <CallNode>[];
    if (entry != null) ordered.add(entry);
    for (final n in flow.nodes) {
      if (n.id == entry?.id) continue;
      if (reachable.contains(n.id)) ordered.add(n);
    }
    for (final n in flow.nodes) {
      if (!reachable.contains(n.id)) ordered.add(n);
    }

    for (final node in ordered) {
      states.add(_exportNode(project, node, reachable.contains(node.id)));
    }

    return {
      'id': flow.id,
      'name': flow.name,
      if (flow.description != null) 'description': flow.description,
      'entry': flow.entryNodeId,
      'states': states,
    };
  }

  /// Maps a single [CallNode] to its Call Control command(s) + transition table.
  Map<String, dynamic> _exportNode(
    CallSystemProject project,
    CallNode node,
    bool reachable,
  ) {
    final transitions = _transitions(node);
    final extraNotes = <String>[];
    if (!reachable) {
      extraNotes.add(
        'Unreachable from entry node; state emitted for '
        'completeness but never entered.',
      );
    }

    // The (command, event→port) pair this node type maps to.
    final mapping = _commandFor(project, node, extraNotes);

    return {
      'nodeId': node.id,
      'type': node.type.name,
      'label': node.label,
      // The Call Control command issued on entering this state (null when the
      // backend has no native command — see notes).
      'command': mapping.command,
      if (mapping.commands.isNotEmpty) 'commands': mapping.commands,
      // port -> targetNodeId (or null when unconnected).
      'transitions': transitions,
      // Maps the Telnyx completion EVENT to the port the dispatcher should take.
      if (mapping.events.isNotEmpty) 'events': mapping.events,
      if (extraNotes.isNotEmpty) 'notes': extraNotes,
    };
  }

  /// The port → targetNodeId map for a node. We start from the canonical
  /// [CallNodeTypeX.basePorts] so every expected port is present (defaulting to
  /// null/unconnected), then overlay the node's actual `outputs` — which for
  /// `menu` nodes also contributes the extra digit/timeout/invalid ports.
  Map<String, String?> _transitions(CallNode node) {
    final out = <String, String?>{for (final p in node.type.basePorts) p: null};
    out.addAll(node.outputs);
    return out;
  }

  // ── Command synthesis per node type ─────────────────────────────────────

  /// Resolves a prompt's spoken text via the project, returning a safe string.
  /// Recorded-only prompts (empty text + audioAssetPath) yield ''.
  String _promptText(CallSystemProject project, String? promptId) {
    if (promptId == null) return '';
    final p = project.promptById(promptId);
    return p?.text ?? '';
  }

  /// True when the referenced prompt is a recorded audio asset (no/blank TTS
  /// text). Such prompts must be played with `playback_start`, not `speak`.
  Prompt? _audioPrompt(CallSystemProject project, String? promptId) {
    if (promptId == null) return null;
    final p = project.promptById(promptId);
    if (p == null) return null;
    final path = p.audioAssetPath;
    if (path != null && path.isNotEmpty && p.text.trim().isEmpty) return p;
    return null;
  }

  /// Builds a `speak` OR `playback_start` command for a promptId, picking the
  /// right one based on whether the prompt is TTS or a recorded asset.
  Map<String, dynamic>? _speakOrPlay(
    CallSystemProject project,
    String? promptId,
  ) {
    if (promptId == null) return null;
    final audio = _audioPrompt(project, promptId);
    if (audio != null) {
      return {
        'command': 'playback_start',
        'payload': {
          // Placeholder: rewrite to where you host the exported audio bundle.
          'audio_url': 'https://YOUR_ASSET_HOST/${audio.audioAssetPath}',
        },
      };
    }
    final text = _promptText(project, promptId);
    if (text.isEmpty) return null;
    final prompt = project.promptById(promptId);
    return {
      'command': 'speak',
      'payload': {
        'payload': text, // Telnyx 'speak' uses the field name "payload".
        'voice': _telnyxVoice(prompt?.voice),
        'language': 'en-US',
      },
    };
  }

  /// Maps a portable kokoro voice id to a Telnyx voice descriptor. Telnyx uses
  /// "Gender.Name" (e.g. "female") or AWS Polly ids; we keep it simple and let
  /// the operator refine. Unknown/null → a sensible default.
  String _telnyxVoice(String? kokoroVoice) {
    if (kokoroVoice == null || kokoroVoice.isEmpty) return 'female';
    // kokoro ids like 'af_heart' (a=american,f=female) — infer gender hint.
    final v = kokoroVoice.toLowerCase();
    if (v.contains('_m') || v.startsWith('am') || v.startsWith('bm')) {
      return 'male';
    }
    return 'female';
  }

  /// Returns the command(s) and event→port hints for a node.
  _NodeCommand _commandFor(
    CallSystemProject project,
    CallNode node,
    List<String> notes,
  ) {
    final cfg = node.config;
    switch (node.type) {
      // ── entry ───────────────────────────────────────────────────────────
      case CallNodeType.entry:
        // The webhook answers the call here; 'next' continues the flow.
        return _NodeCommand(
          command: {'command': 'answer', 'payload': const <String, dynamic>{}},
          events: const {'call.answered': 'next'},
        );

      // ── playPrompt ────────────────────────────────────────────────────────
      case CallNodeType.playPrompt:
        final cmd = _speakOrPlay(project, cfg['promptId'] as String?);
        if (cmd == null) {
          notes.add('playPrompt has no resolvable promptId; emitted as no-op.');
        }
        return _NodeCommand(
          command: cmd,
          events: cmd != null && cmd['command'] == 'playback_start'
              ? const {'call.playback.ended': 'next'}
              : const {'call.speak.ended': 'next'},
        );

      // ── menu (IVR) ────────────────────────────────────────────────────────
      case CallNodeType.menu:
        // gather_using_speak: play the prompt and collect a single DTMF digit.
        // The digit ports live in outputs as extra keys ('1','2',...) plus the
        // base 'timeout'/'invalid' ports.
        final text = _promptText(project, cfg['promptId'] as String?);
        final digits =
            node.outputs.keys
                .where((k) => k != 'timeout' && k != 'invalid')
                .toList()
              ..sort();
        return _NodeCommand(
          command: {
            'command': 'gather_using_speak',
            'payload': {
              'payload': text,
              'voice': _telnyxVoice(
                project.promptById(cfg['promptId'] as String? ?? '')?.voice,
              ),
              'language': 'en-US',
              // Single-digit menu selection.
              'minimum_digits': 1,
              'maximum_digits': 1,
              // Constrain to the configured menu keys when present.
              if (digits.isNotEmpty) 'valid_digits': digits.join(),
              'timeout_millis': 5000,
            },
          },
          // call.gather.ended carries the pressed digit; the dispatcher routes
          // on that digit value. We surface the structural events here.
          events: const {
            'call.gather.ended': '<digit>',
            'call.gather.ended:timeout': 'timeout',
            'call.gather.ended:invalid': 'invalid',
          },
        );

      // ── gatherDigits ──────────────────────────────────────────────────────
      case CallNodeType.gatherDigits:
        final text = _promptText(project, cfg['promptId'] as String?);
        final variable = cfg['variable'] as String?;
        return _NodeCommand(
          command: {
            'command': 'gather_using_speak',
            'payload': {
              if (text.isNotEmpty) 'payload': text,
              'voice': 'female',
              'language': 'en-US',
              'minimum_digits': 1,
              'maximum_digits': 32,
              'timeout_millis': 8000,
              // Where the dispatcher should store the collected digits.
              if (variable != null) 'client_state_variable': variable,
            },
          },
          events: const {
            'call.gather.ended': 'next',
            'call.gather.ended:timeout': 'timeout',
          },
        );

      // ── gatherSpeech ──────────────────────────────────────────────────────
      case CallNodeType.gatherSpeech:
        final text = _promptText(project, cfg['promptId'] as String?);
        final variable = cfg['variable'] as String?;
        notes.add(
          'gatherSpeech uses Telnyx speech recognition (gather with '
          'transcription); confirm STT is enabled on your number/region.',
        );
        return _NodeCommand(
          command: {
            'command': 'gather_using_speak',
            'payload': {
              if (text.isNotEmpty) 'payload': text,
              'voice': 'female',
              'language': 'en-US',
              'speech': {'language': 'en-US'},
              if (variable != null) 'client_state_variable': variable,
            },
          },
          events: const {
            'call.gather.ended': 'next',
            'call.gather.ended:timeout': 'timeout',
            'call.gather.ended:nomatch': 'nomatch',
          },
        );

      // ── aiVoicebot ────────────────────────────────────────────────────────
      case CallNodeType.aiVoicebot:
        final goal = cfg['goal'] as String?;
        notes.add(
          'Bridges call audio to the Omni voicebot via Telnyx media '
          'streaming; next/transfer/hangup are driven by control messages '
          'from the voicebot.',
        );
        return _NodeCommand(
          command: {
            'command': 'streaming_start',
            'payload': {
              // Placeholder: your bidirectional media-streaming endpoint.
              'stream_url': 'wss://YOUR_OMNI_VOICEBOT/stream',
              'stream_track': 'both_tracks',
              'stream_bidirectional_mode': 'rtp',
              if (goal != null) 'client_state_goal': goal,
            },
          },
          events: const {
            'voicebot.continue': 'next',
            'voicebot.transfer': 'transfer',
            'voicebot.hangup': 'hangup',
          },
        );

      // ── dial (external PSTN/SIP) ──────────────────────────────────────────
      case CallNodeType.dial:
        final number = cfg['number'] as String?;
        if (number == null || number.isEmpty) {
          notes.add('dial node missing config[number]; emitted as no-op.');
        }
        return _NodeCommand(
          command: {
            'command': 'dial',
            'payload': {
              'to': number ?? '',
              // from is supplied at runtime (your Telnyx number / CID).
              'from': '\${callerId}',
            },
          },
          events: const {
            'call.dial.answered': 'answered',
            'call.dial.noanswer': 'noanswer',
            'call.dial.busy': 'busy',
            'call.dial.failed': 'failed',
          },
        );

      // ── transferToExtension ───────────────────────────────────────────────
      case CallNodeType.transferToExtension:
        // Resolve the extension to its dialable target (SIP user when present,
        // else the internal number) so the transfer is concrete.
        final extId = cfg['extension'] as String?;
        final ext = extId == null
            ? null
            : _firstWhereOrNull(project.extensions, (e) => e.id == extId);
        final target = ext?.sipUsername != null && ext!.sipUsername!.isNotEmpty
            ? 'sip:${ext.sipUsername}'
            : (ext?.number ?? extId ?? '');
        if (ext == null) {
          notes.add(
            'transferToExtension references unknown extension id '
            '"$extId"; using the raw value as the transfer target.',
          );
        }
        return _NodeCommand(
          command: {
            'command': 'transfer',
            'payload': {
              'to': target,
              'from': '\${callerId}',
              if (ext != null) 'timeout_secs': ext.ringSeconds,
            },
          },
          events: const {
            'call.bridged': 'answered',
            'call.transfer.noanswer': 'noanswer',
            'call.transfer.busy': 'busy',
          },
        );

      // ── ringGroup ─────────────────────────────────────────────────────────
      case CallNodeType.ringGroup:
        final rgId = cfg['ringGroupId'] as String? ?? cfg['target'] as String?;
        final rg = rgId == null
            ? null
            : _firstWhereOrNull(project.ringGroups, (g) => g.id == rgId);
        final targets = <String>[];
        if (rg != null) {
          for (final exId in rg.extensionIds) {
            final ex = _firstWhereOrNull(
              project.extensions,
              (e) => e.id == exId,
            );
            if (ex == null) continue;
            targets.add(
              ex.sipUsername != null && ex.sipUsername!.isNotEmpty
                  ? 'sip:${ex.sipUsername}'
                  : ex.number,
            );
          }
        }
        if (rg == null) {
          notes.add(
            'ringGroup references unknown group id "$rgId"; emitted '
            'with empty member list.',
          );
        } else if (rg.strategy != RingStrategy.ringAll) {
          notes.add(
            'ringGroup "${rg.name}" uses strategy '
            '"${rg.strategy.name}" — Call Control natively rings all at once; '
            'sequential strategies must be sequenced by your webhook (strategy '
            'recorded here).',
          );
        }
        return _NodeCommand(
          command: {
            // ring-all: a single dial to all member targets simultaneously.
            'command': 'dial',
            'payload': {
              'to': targets, // list = simultaneous ring (ring-all)
              'from': '\${callerId}',
              if (rg != null) 'timeout_secs': rg.ringSeconds,
              if (rg != null) 'ring_strategy': rg.strategy.name,
            },
          },
          events: const {
            'call.dial.answered': 'answered',
            'call.dial.noanswer': 'noanswer',
          },
        );

      // ── queue (ACD) ───────────────────────────────────────────────────────
      case CallNodeType.queue:
        final qId = cfg['queueId'] as String? ?? cfg['target'] as String?;
        final q = qId == null
            ? null
            : _firstWhereOrNull(project.queues, (x) => x.id == qId);
        if (q == null) {
          notes.add(
            'queue references unknown queue id "$qId"; emitted as a '
            'generic enqueue.',
          );
        }
        final moh = q?.musicOnHoldPromptId;
        return _NodeCommand(
          command: {
            // Telnyx call queues: enqueue, then your agent logic dequeues.
            'command': 'enqueue',
            'payload': {
              'queue_name': q?.name ?? (qId ?? 'queue'),
              if (q != null) 'max_wait_secs': q.maxWaitSeconds,
              if (q != null) 'agents': q.agentExtensionIds,
              if (q != null) 'ring_strategy': q.strategy.name,
              if (moh != null)
                'hold_audio_url':
                    'https://YOUR_ASSET_HOST/'
                    '${project.promptById(moh)?.audioAssetPath ?? "moh.wav"}',
            },
          },
          events: const {
            'queue.agent.bridged': 'answered',
            'queue.timeout': 'timeout',
            'queue.empty': 'empty',
          },
        );

      // ── voicemail ─────────────────────────────────────────────────────────
      case CallNodeType.voicemail:
        final vmId =
            cfg['voicemailBoxId'] as String? ?? cfg['target'] as String?;
        final vm = vmId == null
            ? null
            : _firstWhereOrNull(project.voicemailBoxes, (v) => v.id == vmId);
        final greeting = vm?.greetingPromptId;
        final greetingCmd = _speakOrPlay(project, greeting);
        notes.add(
          'Voicemail is composed from Call Control primitives: play the '
          'greeting, then record_start with a beep; delivery '
          '(${vm?.emailTo ?? "email"}) happens in your webhook on '
          'call.record.saved.',
        );
        return _NodeCommand(
          command: {
            'command': 'record_start',
            'payload': {
              'format': 'mp3',
              'play_beep': true,
              if (vm?.emailTo != null) 'deliver_to': vm!.emailTo,
              if (vm?.mailboxNumber != null) 'mailbox': vm!.mailboxNumber,
            },
          },
          // Greeting is played first (if any), then recording starts.
          commands: [if (greetingCmd != null) greetingCmd],
          events: const {'call.record.saved': 'done'},
        );

      // ── schedule (time condition) ─────────────────────────────────────────
      case CallNodeType.schedule:
        final tcId =
            cfg['timeConditionId'] as String? ?? cfg['target'] as String?;
        final tc = tcId == null
            ? null
            : _firstWhereOrNull(project.timeConditions, (t) => t.id == tcId);
        notes.add(
          'No Call Control command evaluates business hours. The '
          'dispatcher must evaluate the embedded TimeCondition (timezone + '
          'open ranges + holidays) and pick open/closed/holiday.',
        );
        return _NodeCommand(
          // No command — pure decision the dispatcher makes.
          command: null,
          // Embed the schedule so the webhook can evaluate it without the
          // original project.
          commands: tc == null
              ? const []
              : [
                  {
                    'evaluate': 'time_condition',
                    'timezone': tc.timezone,
                    'openRanges': [
                      for (final r in tc.openRanges)
                        {
                          'days': r.days,
                          'startMinute': r.startMinute,
                          'endMinute': r.endMinute,
                        },
                    ],
                    'holidayDates': tc.holidayDates,
                  },
                ],
          events: const {
            'schedule.open': 'open',
            'schedule.closed': 'closed',
            'schedule.holiday': 'holiday',
          },
        );

      // ── condition (variable branch) ───────────────────────────────────────
      case CallNodeType.condition:
        notes.add(
          'condition is a dispatcher-side branch on a variable/'
          'expression; no Call Control command is issued.',
        );
        return _NodeCommand(
          command: null,
          commands: [
            {
              'evaluate': 'expression',
              if (cfg['variable'] != null) 'variable': cfg['variable'],
              if (cfg['operator'] != null) 'operator': cfg['operator'],
              if (cfg['value'] != null) 'value': cfg['value'],
            },
          ],
          events: const {'condition.true': 'true', 'condition.false': 'false'},
        );

      // ── setVariable ───────────────────────────────────────────────────────
      case CallNodeType.setVariable:
        notes.add(
          'setVariable mutates dispatcher client_state; no Call Control '
          'command is issued.',
        );
        return _NodeCommand(
          command: null,
          commands: [
            {
              'set_variable': cfg['variable'],
              if (cfg.containsKey('value')) 'value': cfg['value'],
            },
          ],
          events: const {'set_variable.done': 'next'},
        );

      // ── httpRequest ───────────────────────────────────────────────────────
      case CallNodeType.httpRequest:
        notes.add(
          'httpRequest is performed by your webhook (out-of-band of the '
          'call media); not a Call Control command.',
        );
        return _NodeCommand(
          command: null,
          commands: [
            {
              'http_request': {
                'method': cfg['method'] ?? 'POST',
                'url': cfg['url'] ?? '',
                if (cfg['body'] != null) 'body': cfg['body'],
              },
            },
          ],
          events: const {
            'http_request.success': 'success',
            'http_request.failure': 'failure',
          },
        );

      // ── record ────────────────────────────────────────────────────────────
      case CallNodeType.record:
        return _NodeCommand(
          command: {
            'command': 'record_start',
            'payload': {'format': 'mp3', 'channels': 'dual'},
          },
          events: const {'call.record.started': 'next'},
        );

      // ── playDirectory (dial-by-name) ──────────────────────────────────────
      case CallNodeType.playDirectory:
        notes.add(
          'Dial-by-name has no native command; emitted as a '
          'gather_using_speak shell. Your webhook matches input to an '
          'extension and bridges.',
        );
        return _NodeCommand(
          command: {
            'command': 'gather_using_speak',
            'payload': {
              'payload':
                  'Please say or enter the name of the person you wish '
                  'to reach.',
              'voice': 'female',
              'language': 'en-US',
            },
          },
          events: const {
            'directory.matched': 'matched',
            'directory.nomatch': 'nomatch',
          },
        );

      // ── hangup ────────────────────────────────────────────────────────────
      case CallNodeType.hangup:
        return _NodeCommand(
          command: {'command': 'hangup', 'payload': const <String, dynamic>{}},
        );

      // ── subFlow ───────────────────────────────────────────────────────────
      case CallNodeType.subFlow:
        final targetFlowId =
            cfg['flowId'] as String? ?? cfg['target'] as String?;
        notes.add(
          'subFlow is a dispatcher push/pop into another flow, not a '
          'Telnyx command; "returned" resumes here when the sub-flow ends.',
        );
        return _NodeCommand(
          command: null,
          commands: [
            {'call_flow': targetFlowId},
          ],
          events: const {'subflow.returned': 'returned'},
        );
    }
  }

  /// Local helper (avoids importing package:collection). Returns the first
  /// element matching [test], or null.
  T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// Internal carrier for a node's mapped Call Control command(s) and the
/// event → port hints the webhook dispatcher uses to advance the state machine.
class _NodeCommand {
  /// The primary command issued on entering the state (null when the node maps
  /// to a dispatcher-side decision with no Call Control command).
  final Map<String, dynamic>? command;

  /// Additional commands (e.g. a greeting before record_start) or embedded
  /// decision descriptors (schedule/condition/http).
  final List<Map<String, dynamic>> commands;

  /// Telnyx event name → port the dispatcher should follow.
  final Map<String, String> events;

  const _NodeCommand({
    this.command,
    this.commands = const [],
    this.events = const {},
  });
}
