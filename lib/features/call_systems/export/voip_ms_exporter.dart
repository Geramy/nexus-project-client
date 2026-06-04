// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../model/call_system_project.dart';
import '../model/call_flow.dart';
import '../model/call_node.dart';
import '../model/pbx_entities.dart';
import 'call_system_exporter.dart';

/// Exports the portable [CallSystemProject] as a voip.ms "deployment plan".
///
/// voip.ms is our preferred PSTN vendor. Unlike a programmable-voice backend
/// (Twilio/Telnyx) where the entire flow can be expressed as code, voip.ms is a
/// *hosted PBX*: you create durable resources (Recordings, IVRs, Ring Groups,
/// Queues, Voicemails) and then point a DID's routing at one of them. Its
/// branching primitive is the IVR — a menu that maps a single DTMF digit to a
/// "destination" string such as `sip:101`, `ringgroup:5`, `ivr:12`,
/// `voicemail:7`, `fwd:+15551234567`, `recording:9`, `queue:3` or `hangup`.
///
/// Because voip.ms has no general expression engine, the imperative parts of a
/// flow (setVariable / condition / httpRequest / gatherSpeech / aiVoicebot)
/// cannot be expressed natively. We map what we can, emit explanatory comments
/// inside the plan, and surface the gaps via [notes]. Anything truly dynamic is
/// expected to run on the Nexus-managed runtime, with voip.ms only carrying the
/// PSTN leg.
///
/// The emitted JSON has two halves:
///  * a declarative `resources` description (recordings, ivrs, ringGroups,
///    queues, voicemails, didRouting) — human-readable and reviewable; and
///  * an `apiCalls` array of {function, params} hints that mirror the voip.ms
///    REST API (setRecording, setIVR, setRingGroup, setQueue, setVoicemail,
///    setDIDRouting) so the managed runtime / a deploy script can replay them.
///
/// IDs in this model are opaque strings (e.g. "vm_main"); voip.ms assigns its
/// own numeric ids on creation. We therefore key destinations by *slug* and
/// leave id resolution to the deploy step (documented in the plan).
class VoipMsExporter implements CallSystemExporter {
  const VoipMsExporter();

  @override
  String get providerKey => 'voip-ms';

  @override
  String get displayName => 'voip.ms';

  @override
  String get artifactExtension => 'json';

  @override
  Map<String, String> export(CallSystemProject project) {
    // Anything the mapping cannot represent gets pushed here and echoed both
    // into the plan (`caveats`) and out of notes().
    final caveats = <String>[];

    // ── 1. Recordings: one per Prompt ──────────────────────────────────
    // voip.ms "Recordings" are reusable audio. TTS prompts carry the text to
    // synthesize (the managed runtime renders kokoro → a WAV then uploads it);
    // recorded prompts carry an asset path to upload directly.
    final recordings = <Map<String, dynamic>>[];
    for (final p in project.prompts) {
      final isRecorded =
          (p.audioAssetPath != null && p.audioAssetPath!.isNotEmpty);
      recordings.add({
        'slug': _recordingSlug(p.id),
        'sourcePromptId': p.id,
        'name': _recordingName(p),
        'kind': isRecorded ? 'audio_asset' : 'tts',
        // For TTS, the text + kokoro voice to synthesize before upload.
        'text': p.text,
        'voice': p.voice,
        // For recorded prompts, the bundle-relative asset to upload as-is.
        'audioAssetPath': p.audioAssetPath,
      });
    }

    // ── 2. Ring groups ─────────────────────────────────────────────────
    // voip.ms ring groups list member SIP accounts and a ring strategy. We map
    // extension ids → SIP destinations (`sip:<number>`), translate the strategy,
    // and route no-answer to the failover voicemail when one is set.
    final ringGroups = <Map<String, dynamic>>[];
    for (final rg in project.ringGroups) {
      ringGroups.add({
        'slug': _ringGroupSlug(rg.id),
        'name': rg.name,
        'number': rg.number,
        'ringStrategy': _ringStrategy(rg.strategy),
        'ringSeconds': rg.ringSeconds,
        'members': rg.extensionIds
            .map((eid) => _extensionDest(project, eid))
            .where((d) => d != null)
            .cast<String>()
            .toList(),
        'failoverDestination': rg.failoverVoicemailBoxId == null
            ? 'hangup'
            : 'voicemail:${_voicemailSlug(rg.failoverVoicemailBoxId!)}',
      });
    }

    // ── 3. Queues ──────────────────────────────────────────────────────
    // voip.ms ACD queues: agents + a ring strategy + a max wait, with an
    // optional music-on-hold recording.
    final queues = <Map<String, dynamic>>[];
    for (final q in project.queues) {
      queues.add({
        'slug': _queueSlug(q.id),
        'name': q.name,
        'number': q.number,
        'ringStrategy': _ringStrategy(q.strategy),
        'maxWaitSeconds': q.maxWaitSeconds,
        'musicOnHold': q.musicOnHoldPromptId == null
            ? null
            : 'recording:${_recordingSlug(q.musicOnHoldPromptId!)}',
        'agents': q.agentExtensionIds
            .map((eid) => _extensionDest(project, eid))
            .where((d) => d != null)
            .cast<String>()
            .toList(),
      });
    }

    // ── 4. Voicemails ──────────────────────────────────────────────────
    // voip.ms voicemail boxes have a mailbox number, an optional greeting
    // recording, and optional email delivery.
    final voicemails = <Map<String, dynamic>>[];
    for (final vb in project.voicemailBoxes) {
      voicemails.add({
        'slug': _voicemailSlug(vb.id),
        'name': vb.name,
        'mailbox': vb.mailboxNumber,
        'greeting': vb.greetingPromptId == null
            ? null
            : 'recording:${_recordingSlug(vb.greetingPromptId!)}',
        'emailTo': vb.emailTo,
      });
    }

    // ── 5. IVRs: one per `menu` node across all flows ──────────────────
    // The menu node is voip.ms's natural fit: play a recording, gather a digit,
    // branch. We walk every flow from its entryNode, collect menu nodes, and
    // turn each into an IVR whose `digitMap` maps "1"/"2"/… (plus timeout /
    // invalid) to a resolved voip.ms destination string. Non-menu nodes are
    // collapsed into a single destination via [_resolveDestination].
    final ivrs = <Map<String, dynamic>>[];
    final seenMenuNodes = <String>{};
    for (final flow in project.flows) {
      final entry = flow.entryNode;
      if (entry == null) continue;
      for (final node in _walk(flow)) {
        if (node.type != CallNodeType.menu) continue;
        // Globally unique slug: a node id is unique only within its flow.
        final menuKey = '${flow.id}:${node.id}';
        if (!seenMenuNodes.add(menuKey)) continue;

        // The greeting recording for the menu (config['promptId']).
        final promptId = node.config['promptId'] as String?;
        final greeting =
            (promptId != null && project.promptById(promptId) != null)
            ? 'recording:${_recordingSlug(promptId)}'
            : null;

        // Digit map: every output port that is NOT a base port (timeout/invalid)
        // is a DTMF key on a menu node. We also carry timeout/invalid explicitly.
        final digitMap = <String, dynamic>{};
        final basePorts = CallNodeType.menu.basePorts; // ['timeout','invalid']
        node.outputs.forEach((port, targetId) {
          if (basePorts.contains(port)) return; // handled below
          digitMap[port] = _resolveDestination(
            project,
            flow,
            targetId,
            caveats,
          );
        });

        ivrs.add({
          'slug': _ivrSlug(flow.id, node.id),
          'name': node.label.isEmpty ? 'IVR ${node.id}' : node.label,
          'sourceFlowId': flow.id,
          'sourceNodeId': node.id,
          'greeting': greeting,
          'digitMap': digitMap,
          'timeoutDestination': _resolveDestination(
            project,
            flow,
            node.outputs['timeout'],
            caveats,
          ),
          'invalidDestination': _resolveDestination(
            project,
            flow,
            node.outputs['invalid'],
            caveats,
          ),
        });
      }
    }

    // ── 6. DID routing: each Did → its flow's entry destination ────────
    // A DID points at whatever its flow's entry leads to. The entry node itself
    // is a no-op marker, so we resolve its 'next' output into a concrete
    // destination (often an IVR slug, a ring group, or a recording).
    final didRouting = <Map<String, dynamic>>[];
    for (final did in project.dids) {
      String destination;
      final flow = did.flowId == null ? null : project.flowById(did.flowId!);
      if (flow == null) {
        destination = 'hangup';
        caveats.add(
          'DID ${did.e164} has no flow assigned; routed to hangup. Assign a '
          'flow or set routing manually in voip.ms.',
        );
      } else {
        final entry = flow.entryNode;
        // Entry is a pass-through: follow its single 'next' port.
        final firstTargetId = entry?.outputs['next'];
        destination = _resolveDestination(
          project,
          flow,
          firstTargetId,
          caveats,
        );
      }
      didRouting.add({
        'did': did.e164,
        'label': did.label,
        'flowId': did.flowId,
        // Whether Nexus provisions this number (managed) or the user owns it.
        'managed': did.managed,
        'routing': destination,
      });
    }

    // ── 7. apiCalls: replayable voip.ms REST hints ─────────────────────
    // These mirror the voip.ms API method names so a deploy step can iterate the
    // array in order. Recordings/voicemails/groups/queues/ivrs must exist before
    // DID routing references them, so we emit them first.
    final apiCalls = <Map<String, dynamic>>[];
    for (final r in recordings) {
      apiCalls.add({
        'function': 'setRecording',
        'params': {
          'name': r['name'],
          'slug': r['slug'],
          if (r['kind'] == 'tts') 'tts_text': r['text'],
          if (r['kind'] == 'tts') 'tts_voice': r['voice'],
          if (r['kind'] == 'audio_asset') 'file': r['audioAssetPath'],
        },
      });
    }
    for (final vb in voicemails) {
      apiCalls.add({
        'function': 'setVoicemail',
        'params': {
          'mailbox': vb['mailbox'],
          'name': vb['name'],
          'slug': vb['slug'],
          'email': vb['emailTo'],
          'greeting': vb['greeting'],
        },
      });
    }
    for (final rg in ringGroups) {
      apiCalls.add({
        'function': 'setRingGroup',
        'params': {
          'name': rg['name'],
          'slug': rg['slug'],
          'members': rg['members'],
          'ring_strategy': rg['ringStrategy'],
          'ring_time': rg['ringSeconds'],
          'failover': rg['failoverDestination'],
        },
      });
    }
    for (final q in queues) {
      apiCalls.add({
        'function': 'setQueue',
        'params': {
          'name': q['name'],
          'slug': q['slug'],
          'agents': q['agents'],
          'ring_strategy': q['ringStrategy'],
          'maximum_wait_time': q['maxWaitSeconds'],
          'moh': q['musicOnHold'],
        },
      });
    }
    for (final ivr in ivrs) {
      apiCalls.add({
        'function': 'setIVR',
        'params': {
          'name': ivr['name'],
          'slug': ivr['slug'],
          'recording': ivr['greeting'],
          'choices': ivr['digitMap'],
          'timeout': ivr['timeoutDestination'],
          'invalid': ivr['invalidDestination'],
        },
      });
    }
    for (final route in didRouting) {
      apiCalls.add({
        'function': 'setDIDRouting',
        'params': {'did': route['did'], 'routing': route['routing']},
      });
    }

    // Merge in the static, structural caveats so they always travel with the
    // plan even on a trivial project.
    final allCaveats = <String>{
      ..._structuralCaveats(project),
      ...caveats,
    }.toList();

    final plan = <String, dynamic>{
      'provider': providerKey,
      'displayName': displayName,
      'kind': 'voip.ms-deployment-plan',
      'schemaVersion': 1,
      'project': {
        'name': project.name,
        'subCategory': project.subCategory.name,
        'experienceMode': project.experienceMode,
        'isOutbound': project.isOutbound,
      },
      // Free-form key/value defaults the runtime may substitute into prompts.
      'variables': project.variables,
      'resources': {
        'recordings': recordings,
        'ivrs': ivrs,
        'ringGroups': ringGroups,
        'queues': queues,
        'voicemails': voicemails,
        'didRouting': didRouting,
      },
      'apiCalls': apiCalls,
      'caveats': allCaveats,
    };

    return {
      'voip_ms_deployment_plan.json': const JsonEncoder.withIndent(
        '  ',
      ).convert(plan),
    };
  }

  @override
  List<String> notes(CallSystemProject project) {
    final n = <String>[
      'Number provisioning and per-minute / DID pricing are handled by the '
          'Nexus-managed runtime through the Router; this plan does not buy '
          'numbers or set rates. Managed DIDs are ordered for you, and '
          'unmanaged DIDs assume you already own the number on voip.ms.',
      'voip.ms is a hosted PBX, not a programmable-voice engine. Each `menu` '
          'node becomes a voip.ms IVR (digit → destination). Non-branching '
          'nodes are collapsed into a single destination string.',
      'Conversational/dynamic nodes (aiVoicebot, gatherSpeech, condition, '
          'setVariable, httpRequest, subFlow) have no native voip.ms equivalent. '
          'They are surfaced as caveats and must run on the Nexus runtime, with '
          'voip.ms carrying only the PSTN leg (e.g. SIP/forward into Omni).',
      'Resource ids are emitted as stable slugs; voip.ms assigns numeric ids on '
          'creation. The deploy step must resolve slug → id before wiring '
          'destinations and DID routing.',
    ];
    // Echo the per-project structural caveats so the UI surface is complete.
    n.addAll(_structuralCaveats(project));
    return n;
  }

  // ── Destination resolution ──────────────────────────────────────────

  /// Resolve a target node id into a voip.ms destination string. This collapses
  /// a chain of non-branching nodes (entry → playPrompt → transfer, etc.) into a
  /// single destination, because voip.ms can only store ONE destination per
  /// slot. Branching is only possible at IVR (menu) nodes, which are emitted
  /// separately and referenced here via `ivr:<slug>`.
  String _resolveDestination(
    CallSystemProject project,
    CallFlow flow,
    String? nodeId,
    List<String> caveats, [
    int depth = 0,
  ]) {
    if (nodeId == null) return 'hangup';
    if (depth > 64) {
      caveats.add(
        'Flow "${flow.name}" exceeds the resolution depth limit at node '
        '$nodeId (possible loop); routed to hangup.',
      );
      return 'hangup';
    }
    final node = flow.nodeById(nodeId);
    if (node == null) return 'hangup';

    switch (node.type) {
      case CallNodeType.menu:
        // A menu is its own IVR resource; reference it.
        return 'ivr:${_ivrSlug(flow.id, node.id)}';

      case CallNodeType.entry:
      case CallNodeType.playPrompt:
      case CallNodeType.record:
      case CallNodeType.setVariable:
        // Pass-through nodes. For playPrompt we'd ideally chain "play then go
        // to next", but voip.ms slots hold a single destination, so we surface
        // the recording-then-route limitation and follow 'next'.
        if (node.type == CallNodeType.playPrompt) {
          final pid = node.config['promptId'] as String?;
          if (pid != null && project.promptById(pid) != null) {
            // If 'next' is unconnected, the recording IS the destination.
            final next = node.outputs['next'];
            if (next == null) {
              return 'recording:${_recordingSlug(pid)}';
            }
            caveats.add(
              'playPrompt "${node.label}" in flow "${flow.name}": voip.ms cannot '
              'play a recording then continue inline; the prompt is dropped and '
              'the call routes straight to the next step. Bake the prompt into '
              'the destination IVR/voicemail greeting instead.',
            );
          }
        }
        if (node.type == CallNodeType.setVariable) {
          caveats.add(
            'setVariable "${node.label}" in flow "${flow.name}" has no voip.ms '
            'equivalent and is skipped (variable state requires the Nexus '
            'runtime).',
          );
        }
        if (node.type == CallNodeType.record) {
          caveats.add(
            'record node "${node.label}" in flow "${flow.name}": enable call '
            'recording on the DID/route in voip.ms; check recording-consent '
            'rules for the jurisdiction.',
          );
        }
        return _resolveDestination(
          project,
          flow,
          node.outputs['next'],
          caveats,
          depth + 1,
        );

      case CallNodeType.transferToExtension:
        final ext = node.config['extension'] as String?;
        if (ext != null && ext.isNotEmpty) return 'sip:$ext';
        // Fall back to a referenced extension entity if id-style config is used.
        final dest = _extensionDest(project, ext ?? '');
        return dest ?? 'hangup';

      case CallNodeType.dial:
        final number = node.config['number'] as String?;
        if (number != null && number.isNotEmpty) return 'fwd:$number';
        caveats.add(
          'dial node "${node.label}" in flow "${flow.name}" has no number; '
          'routed to hangup.',
        );
        return 'hangup';

      case CallNodeType.ringGroup:
        // Prefer an explicit ring-group id in config; else the first defined.
        final rgId =
            node.config['ringGroupId'] as String? ??
            (project.ringGroups.isNotEmpty
                ? project.ringGroups.first.id
                : null);
        if (rgId != null) return 'ringgroup:${_ringGroupSlug(rgId)}';
        return 'hangup';

      case CallNodeType.queue:
        final qId =
            node.config['queueId'] as String? ??
            (project.queues.isNotEmpty ? project.queues.first.id : null);
        if (qId != null) return 'queue:${_queueSlug(qId)}';
        return 'hangup';

      case CallNodeType.voicemail:
        final vbId =
            node.config['voicemailBoxId'] as String? ??
            (project.voicemailBoxes.isNotEmpty
                ? project.voicemailBoxes.first.id
                : null);
        if (vbId != null) return 'voicemail:${_voicemailSlug(vbId)}';
        return 'hangup';

      case CallNodeType.schedule:
        // voip.ms has Time Conditions, but mapping the full ruleset to its
        // limited model is lossy; route to the 'open' branch and warn.
        caveats.add(
          'schedule node "${node.label}" in flow "${flow.name}": create a '
          'matching voip.ms Time Condition manually. The plan routes to the '
          '"open" branch by default.',
        );
        return _resolveDestination(
          project,
          flow,
          node.outputs['open'] ?? node.outputs['closed'],
          caveats,
          depth + 1,
        );

      case CallNodeType.playDirectory:
        // voip.ms supports dial-by-name; expose as a sentinel destination.
        return 'directory';

      case CallNodeType.hangup:
        return 'hangup';

      case CallNodeType.gatherDigits:
        caveats.add(
          'gatherDigits node "${node.label}" in flow "${flow.name}": voip.ms '
          'IVRs gather a single menu digit only, not free-form input. Modeled '
          'as a routed continuation; multi-digit collection needs the Nexus '
          'runtime.',
        );
        return _resolveDestination(
          project,
          flow,
          node.outputs['next'],
          caveats,
          depth + 1,
        );

      case CallNodeType.aiVoicebot:
        // The conversational path lives on Nexus; voip.ms forwards the leg in.
        caveats.add(
          'aiVoicebot node "${node.label}" in flow "${flow.name}" '
          '(goal: ${node.config['goal'] ?? 'unspecified'}) routes to the Nexus '
          'managed runtime (Omni). voip.ms only carries the PSTN/SIP leg.',
        );
        return 'nexus:voicebot:${flow.id}:${node.id}';

      case CallNodeType.gatherSpeech:
      case CallNodeType.condition:
      case CallNodeType.httpRequest:
      case CallNodeType.subFlow:
        caveats.add(
          '${node.type.name} node "${node.label}" in flow "${flow.name}" has no '
          'voip.ms equivalent; deploy this flow on the Nexus managed runtime. '
          'The plan routes the call to Nexus for this step.',
        );
        return 'nexus:${node.type.name}:${flow.id}:${node.id}';
    }
  }

  /// Map an extension *id* to a voip.ms SIP destination by looking up its number.
  /// Returns null if the id is unknown (callers filter nulls / fall back).
  String? _extensionDest(CallSystemProject project, String extensionId) {
    for (final e in project.extensions) {
      if (e.id == extensionId) return 'sip:${e.number}';
    }
    // Some configs may already hold a literal number rather than an id.
    if (extensionId.isNotEmpty && RegExp(r'^\d+$').hasMatch(extensionId)) {
      return 'sip:$extensionId';
    }
    return null;
  }

  // ── Flow traversal ──────────────────────────────────────────────────

  /// Breadth-first walk of all nodes reachable from the flow's entry, following
  /// every non-null output edge. Used to discover menu nodes for IVR emission.
  Iterable<CallNode> _walk(CallFlow flow) {
    final entry = flow.entryNode;
    if (entry == null) return const [];
    final seen = <String>{};
    final order = <CallNode>[];
    final stack = <String>[entry.id];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!seen.add(id)) continue;
      final node = flow.nodeById(id);
      if (node == null) continue;
      order.add(node);
      for (final target in node.outputs.values) {
        if (target != null && !seen.contains(target)) stack.add(target);
      }
    }
    return order;
  }

  // ── Strategy translation ────────────────────────────────────────────

  /// Map our [RingStrategy] onto the closest voip.ms strategy keyword. voip.ms
  /// offers a smaller set, so several portable strategies collapse onto one.
  String _ringStrategy(RingStrategy s) {
    switch (s) {
      case RingStrategy.ringAll:
        return 'ringall';
      case RingStrategy.hunt:
      case RingStrategy.memoryHunt:
        return 'hunt'; // sequential; memoryHunt's accumulation isn't exposed
      case RingStrategy.roundRobin:
        return 'rrmemory';
      case RingStrategy.fewestRecent:
        return 'leastrecent';
      case RingStrategy.random:
        return 'random';
    }
  }

  // ── Project-level structural caveats ────────────────────────────────

  /// Caveats that depend only on which entities exist (independent of flow
  /// traversal), so they're available to both export() and notes().
  List<String> _structuralCaveats(CallSystemProject project) {
    final c = <String>[];
    if (project.pickupGroups.isNotEmpty) {
      c.add(
        'Pickup groups (${project.pickupGroups.length}) are not modeled by this '
        'plan; configure *8 directed-pickup feature codes in voip.ms manually.',
      );
    }
    if (project.parkGroups.isNotEmpty) {
      c.add(
        'Park/hold groups (${project.parkGroups.length}) are not modeled; set '
        'up call-parking slots in voip.ms manually.',
      );
    }
    if (project.timeConditions.isNotEmpty) {
      c.add(
        'Time conditions (${project.timeConditions.length}) must be recreated as '
        'voip.ms Time Conditions; their full rules (holidays, multiple ranges) '
        'may need manual adjustment.',
      );
    }
    if (project.isOutbound) {
      c.add(
        'This is an outbound sub-category (${project.subCategory.name}). voip.ms '
        'carries outbound calls, but TCPA/consent/DNC compliance is enforced by '
        'the Nexus runtime, not by this plan.',
      );
    }
    return c;
  }

  // ── Slug helpers (stable, filesystem/URL-safe identifiers) ──────────

  String _slug(String raw) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'x' : s;
  }

  String _recordingSlug(String promptId) => 'rec_${_slug(promptId)}';
  String _ringGroupSlug(String id) => 'rg_${_slug(id)}';
  String _queueSlug(String id) => 'q_${_slug(id)}';
  String _voicemailSlug(String id) => 'vm_${_slug(id)}';
  String _ivrSlug(String flowId, String nodeId) =>
      'ivr_${_slug(flowId)}_${_slug(nodeId)}';

  String _recordingName(Prompt p) {
    if (p.text.isNotEmpty) {
      final t = p.text.length > 40 ? '${p.text.substring(0, 40)}…' : p.text;
      return t;
    }
    return 'Prompt ${p.id}';
  }
}
