// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../model/call_system_project.dart';
import '../model/call_flow.dart';
import '../model/call_node.dart';
import 'call_system_exporter.dart';

/// Exports the portable [CallSystemProject] to an **Amazon Connect Contact
/// Flow** JSON document.
///
/// Amazon Connect models a flow as a flat list of "Actions" (also called blocks
/// in the Connect UI). Each Action has:
///   - an `Identifier` (we reuse our node ids verbatim so transitions line up),
///   - a `Type` (the Connect block type, e.g. `MessageParticipant`),
///   - a `Parameters` object (block-specific config),
///   - a `Transitions` object: `{ NextAction, Errors: [...], Conditions: [...] }`.
///
/// The top-level document is `{ Version, StartAction, Actions: [...] }`.
///
/// IMPORTANT: Connect's published flow-language schema is large and AWS evolves
/// the exact field names (this is approximated from the public Contact Flow
/// language). The output here is structurally faithful and import-shaped, but
/// `notes()` flags that the precise field names must be validated against the
/// current Connect "Contact flow language" before importing into a live
/// instance. We therefore favor a clean, predictable mapping over guessing at
/// every optional AWS parameter.
class AmazonConnectExporter implements CallSystemExporter {
  const AmazonConnectExporter();

  @override
  String get providerKey => 'amazon-connect';

  @override
  String get displayName => 'Amazon Connect (Contact Flow)';

  @override
  String get artifactExtension => 'json';

  // Connect block type constants — kept as named strings so the mapping reads
  // clearly and a single edit updates every emission site.
  static const _typeMessage = 'MessageParticipant'; // play TTS / prompt audio
  static const _typeGetInput = 'GetParticipantInput'; // IVR menu / DTMF gather
  static const _typeTransferToFlow = 'TransferToFlow'; // jump to another flow
  static const _typeTransferToQueue = 'TransferContactToQueue'; // ACD queue
  static const _typeDisconnect = 'DisconnectParticipant'; // hang up
  static const _typeUpdateContactData = 'UpdateContactData'; // setVariable etc.
  static const _typeInvokeLambda = 'InvokeLambdaFunction'; // httpRequest / AI
  static const _typeCheckHoursOfOp = 'CheckHoursOfOperation'; // schedule
  static const _typeCompareContactAttributes = // condition branch
      'CompareContactAttributes';

  @override
  Map<String, String> export(CallSystemProject project) {
    final files = <String, String>{};

    // Connect imports one Contact Flow per file. We emit one document per flow
    // in the project so multi-flow projects round-trip as a set of artifacts.
    for (final flow in project.flows) {
      final doc = _buildFlowDocument(project, flow);
      final fileName =
          '${_safeFileName(flow.name.isEmpty ? flow.id : flow.name)}'
          '.contactflow.json';
      files[fileName] = const JsonEncoder.withIndent('  ').convert(doc);
    }

    // If the project has no flows there is nothing Connect-shaped to emit, but
    // we still produce a stub so the export never yields an empty archive.
    if (files.isEmpty) {
      files['empty.contactflow.json'] = const JsonEncoder.withIndent('  ')
          .convert(<String, dynamic>{
            'Version': '2019-10-30',
            'StartAction': '',
            'Actions': <dynamic>[],
          });
    }

    return files;
  }

  /// Build a single Connect Contact Flow document for [flow].
  Map<String, dynamic> _buildFlowDocument(
    CallSystemProject project,
    CallFlow flow,
  ) {
    final actions = <Map<String, dynamic>>[];

    // Walk the graph starting from the entry node, following `outputs`, so we
    // only emit reachable nodes (Connect rejects orphaned/dangling references).
    // A visited-set guards against cycles (menus that loop back, retries, etc.).
    final visited = <String>{};
    final queue = <String>[];

    final entry = flow.entryNode;
    if (entry != null) {
      queue.add(entry.id);
    }

    // `StartAction` must point at the first *real* Connect block. Our `entry`
    // node is a pure marker (Connect has no entry block), so we resolve through
    // it to its `next` target and use that as the start; if entry already is a
    // real node we keep it.
    String startActionId = '';

    while (queue.isNotEmpty) {
      final nodeId = queue.removeAt(0);
      if (visited.contains(nodeId)) continue;
      visited.add(nodeId);

      final node = flow.nodeById(nodeId);
      if (node == null) continue;

      // The `entry` node carries no Connect semantics: skip emitting a block
      // for it but record its successor as the flow's StartAction and continue
      // the walk from there.
      if (node.type == CallNodeType.entry) {
        final next = node.outputs['next'];
        if (next != null) {
          if (startActionId.isEmpty) startActionId = next;
          queue.add(next);
        }
        continue;
      }

      // First emitted block (when entry resolved to it, or there was no entry)
      // becomes the StartAction if we haven't set one yet.
      if (startActionId.isEmpty) startActionId = node.id;

      final mapped = _mapNode(project, node);
      actions.add(mapped.action);

      // Enqueue every downstream target so the BFS covers the whole reachable
      // graph. We enqueue the raw output target ids (Connect transitions point
      // at the same ids we used as Identifiers).
      for (final target in node.outputs.values) {
        if (target != null && !visited.contains(target)) {
          queue.add(target);
        }
      }
    }

    return <String, dynamic>{
      'Version': '2019-10-30',
      'StartAction': startActionId,
      'Metadata': <String, dynamic>{
        'name': flow.name,
        if (flow.description != null) 'description': flow.description,
        'exportedBy': 'Nexus Projects call-system builder',
        'provider': providerKey,
      },
      'Actions': actions,
    };
  }

  /// Result of mapping one node: the Connect Action map. (Wrapped so we could
  /// add side-channel data later without changing call sites.)
  _MappedNode _mapNode(CallSystemProject project, CallNode node) {
    switch (node.type) {
      // ---- Play a prompt -> MessageParticipant ---------------------------
      case CallNodeType.playPrompt:
        return _MappedNode(
          _action(node, _typeMessage, {
            'Text': _promptText(project, node),
          }, _linearTransition(node)),
        );

      // ---- IVR menu -> GetParticipantInput -------------------------------
      // Connect's input block plays a prompt, collects DTMF, then branches via
      // `Conditions`. We map each digit port to an Equals condition and the
      // `timeout`/`invalid` ports to the block's error/timeout transitions.
      case CallNodeType.menu:
        return _MappedNode(
          _action(node, _typeGetInput, {
            'Text': _promptText(project, node),
            'InputType': 'DTMF',
            'MaxDigits': 1,
          }, _menuTransitions(node)),
        );

      // ---- Gather DTMF / speech into a variable --------------------------
      // Both map to GetParticipantInput storing into a contact attribute named
      // after the configured variable.
      case CallNodeType.gatherDigits:
      case CallNodeType.gatherSpeech:
        final variable = (node.config['variable'] as String?) ?? 'userInput';
        return _MappedNode(
          _action(
            node,
            _typeGetInput,
            {
              'InputType': node.type == CallNodeType.gatherDigits
                  ? 'DTMF'
                  : 'Speech',
              'StoreInput': true,
              'DestinationKey': variable,
              if (project.promptById(
                    node.config['promptId'] as String? ?? '',
                  ) !=
                  null)
                'Text': _promptText(project, node),
            },
            // gather's base ports are next/timeout (+nomatch for speech).
            _gatherTransitions(node),
          ),
        );

      // ---- Dial external number -> TransferToFlow ------------------------
      // Connect has no first-class "dial a PSTN number and bridge" block in the
      // flow language the way Twilio does; outbound bridging is typically a
      // transfer to a flow/quick-connect. We approximate with TransferToFlow
      // and stash the target number as a parameter; notes() flags the caveat.
      case CallNodeType.dial:
        final number = (node.config['number'] as String?) ?? '';
        return _MappedNode(
          _action(node, _typeTransferToFlow, {
            'ContactFlowId': '',
            'DialNumber': number,
          }, _dialTransitions(node)),
        );

      // ---- Transfer to internal extension -> TransferToFlow --------------
      case CallNodeType.transferToExtension:
        final ext = (node.config['extension'] as String?) ?? '';
        return _MappedNode(
          _action(node, _typeTransferToFlow, {
            'ContactFlowId': '',
            'Extension': ext,
          }, _dialTransitions(node)),
        );

      // ---- Ring group -> TransferContactToQueue --------------------------
      // Connect routes by queue, not by ad-hoc ring group, so a ring group is
      // expressed as a transfer to a queue named after the group.
      case CallNodeType.ringGroup:
        return _MappedNode(
          _action(
            node,
            _typeTransferToQueue,
            {'QueueId': node.id, 'QueueName': node.label},
            _queueTransitions(node, answered: 'answered', other: 'noanswer'),
          ),
        );

      // ---- ACD queue -> TransferContactToQueue ---------------------------
      case CallNodeType.queue:
        return _MappedNode(
          _action(
            node,
            _typeTransferToQueue,
            {'QueueId': node.id, 'QueueName': node.label},
            _queueTransitions(node, answered: 'answered', other: 'timeout'),
          ),
        );

      // ---- Voicemail -----------------------------------------------------
      // Connect voicemail is an AWS add-on (typically Lambda + Amazon
      // Connect Customer Profiles / Pinpoint). We emit a MessageParticipant
      // greeting then disconnect via the `done` port; full voicemail capture
      // requires the Connect voicemail solution (noted in notes()).
      case CallNodeType.voicemail:
        return _MappedNode(
          _action(
            node,
            _typeMessage,
            {
              'Text': 'Please leave a message after the tone.',
              '_nexusVoicemail': true,
            },
            {'NextAction': node.outputs['done'] ?? ''},
          ),
        );

      // ---- Schedule / business hours -> CheckHoursOfOperation ------------
      case CallNodeType.schedule:
        return _MappedNode(
          _action(node, _typeCheckHoursOfOp, {
            'HoursOfOperationId': node.id,
          }, _scheduleTransitions(node)),
        );

      // ---- Condition -> CompareContactAttributes -------------------------
      case CallNodeType.condition:
        return _MappedNode(
          _action(node, _typeCompareContactAttributes, {
            'ComparisonValue': node.config['variable'] ?? '',
          }, _conditionTransitions(node)),
        );

      // ---- Set variable -> UpdateContactData -----------------------------
      case CallNodeType.setVariable:
        return _MappedNode(
          _action(node, _typeUpdateContactData, {
            'Attribute': node.config['variable'] ?? '',
            'Value': node.config['value'] ?? '',
          }, _linearTransition(node)),
        );

      // ---- HTTP request -> InvokeLambdaFunction --------------------------
      // Connect cannot call arbitrary HTTP endpoints directly; the idiom is a
      // Lambda proxy. We emit an InvokeLambdaFunction block carrying the URL.
      case CallNodeType.httpRequest:
        return _MappedNode(
          _action(node, _typeInvokeLambda, {
            'FunctionArn': '',
            '_nexusHttpUrl': node.config['url'] ?? '',
          }, _successFailureTransitions(node)),
        );

      // ---- AI voicebot -> InvokeLambdaFunction ---------------------------
      // The conversational AI turn (Omni) is realized in Connect through a
      // Lambda/Lex bridge. We surface the configured goal so the integrator can
      // wire it to Lex/Bedrock. notes() flags that this is not a 1:1 block.
      case CallNodeType.aiVoicebot:
        return _MappedNode(
          _action(
            node,
            _typeInvokeLambda,
            {'FunctionArn': '', '_nexusAiGoal': node.config['goal'] ?? ''},
            {
              'NextAction': node.outputs['next'] ?? '',
              'Conditions': [
                if (node.outputs['transfer'] != null)
                  {
                    'Operator': 'Equals',
                    'Operands': ['transfer'],
                    'NextAction': node.outputs['transfer'],
                  },
                if (node.outputs['hangup'] != null)
                  {
                    'Operator': 'Equals',
                    'Operands': ['hangup'],
                    'NextAction': node.outputs['hangup'],
                  },
              ],
            },
          ),
        );

      // ---- Record -> approximate with a contact-attribute flag -----------
      // Connect call recording is configured via the "Set recording behavior"
      // block; we approximate with UpdateContactData and note the manual step.
      case CallNodeType.record:
        return _MappedNode(
          _action(node, _typeUpdateContactData, {
            'Attribute': 'recordingBehavior',
            'Value': 'Enable',
          }, _linearTransition(node)),
        );

      // ---- Dial-by-name directory ----------------------------------------
      // No native Connect equivalent; emit a GetParticipantInput placeholder
      // and flag it in notes() for manual buildout.
      case CallNodeType.playDirectory:
        return _MappedNode(
          _action(
            node,
            _typeGetInput,
            {
              'InputType': 'DTMF',
              '_nexusUnsupported': 'dial-by-name directory',
            },
            {
              'NextAction': node.outputs['matched'] ?? '',
              'Errors': [
                {
                  'ErrorType': 'NoMatchingError',
                  'NextAction': node.outputs['nomatch'] ?? '',
                },
              ],
            },
          ),
        );

      // ---- Sub-flow -> TransferToFlow ------------------------------------
      case CallNodeType.subFlow:
        return _MappedNode(
          _action(
            node,
            _typeTransferToFlow,
            {'ContactFlowId': node.config['flowId'] ?? ''},
            {'NextAction': node.outputs['returned'] ?? ''},
          ),
        );

      // ---- Hangup -> DisconnectParticipant -------------------------------
      case CallNodeType.hangup:
        return _MappedNode(
          _action(
            node,
            _typeDisconnect,
            const {},
            const {}, // terminal block: no transitions
          ),
        );

      // ---- Entry is handled in the walker and never reaches here ----------
      case CallNodeType.entry:
        return _MappedNode(
          _action(node, _typeMessage, const {
            '_nexusNote': 'entry marker',
          }, _linearTransition(node)),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Transition builders. Connect expresses branching via three keys on the
  // `Transitions` object: `NextAction` (the happy path / fall-through),
  // `Errors` (typed failures), and `Conditions` (value-based branches).
  // ---------------------------------------------------------------------------

  /// Single linear successor over the `next` port.
  Map<String, dynamic> _linearTransition(CallNode node) => {
    'NextAction': node.outputs['next'] ?? '',
  };

  /// Menu: each configured digit port becomes an Equals condition; `timeout`
  /// and `invalid` become typed errors.
  Map<String, dynamic> _menuTransitions(CallNode node) {
    final conditions = <Map<String, dynamic>>[];
    // Menu digit ports are the extra keys beyond the base ports.
    const reserved = {'timeout', 'invalid'};
    for (final entry in node.outputs.entries) {
      if (reserved.contains(entry.key)) continue;
      if (entry.value == null) continue;
      conditions.add({
        'Operator': 'Equals',
        'Operands': [entry.key],
        'NextAction': entry.value,
      });
    }
    return {
      'Conditions': conditions,
      'Errors': [
        {
          'ErrorType': 'InputTimeLimitExceeded',
          'NextAction': node.outputs['timeout'] ?? '',
        },
        {
          'ErrorType': 'NoMatchingCondition',
          'NextAction': node.outputs['invalid'] ?? '',
        },
      ],
    };
  }

  /// gatherDigits / gatherSpeech transitions.
  Map<String, dynamic> _gatherTransitions(CallNode node) => {
    'NextAction': node.outputs['next'] ?? '',
    'Errors': [
      {
        'ErrorType': 'InputTimeLimitExceeded',
        'NextAction': node.outputs['timeout'] ?? '',
      },
      if (node.outputs.containsKey('nomatch'))
        {
          'ErrorType': 'NoMatchingError',
          'NextAction': node.outputs['nomatch'] ?? '',
        },
    ],
  };

  /// dial / transferToExtension transitions: answered is the happy path; the
  /// noanswer/busy/failed ports map to typed errors.
  Map<String, dynamic> _dialTransitions(CallNode node) => {
    'NextAction': node.outputs['answered'] ?? '',
    'Errors': [
      if (node.outputs['noanswer'] != null)
        {'ErrorType': 'NoAnswer', 'NextAction': node.outputs['noanswer']},
      if (node.outputs['busy'] != null)
        {'ErrorType': 'Busy', 'NextAction': node.outputs['busy']},
      if (node.outputs['failed'] != null)
        {'ErrorType': 'CallFailed', 'NextAction': node.outputs['failed']},
    ],
  };

  /// queue / ringGroup transitions.
  Map<String, dynamic> _queueTransitions(
    CallNode node, {
    required String answered,
    required String other,
  }) => {
    'NextAction': node.outputs[answered] ?? '',
    'Errors': [
      if (node.outputs[other] != null)
        {'ErrorType': 'QueueAtCapacity', 'NextAction': node.outputs[other]},
      if (node.outputs['empty'] != null)
        {'ErrorType': 'NoAgentsAvailable', 'NextAction': node.outputs['empty']},
    ],
  };

  /// schedule (CheckHoursOfOperation) branches on open/closed/holiday.
  Map<String, dynamic> _scheduleTransitions(CallNode node) => {
    'NextAction': node.outputs['open'] ?? '',
    'Conditions': [
      if (node.outputs['closed'] != null)
        {
          'Operator': 'Equals',
          'Operands': ['False'],
          'NextAction': node.outputs['closed'],
        },
      if (node.outputs['holiday'] != null)
        {
          'Operator': 'Equals',
          'Operands': ['Holiday'],
          'NextAction': node.outputs['holiday'],
        },
    ],
  };

  /// condition (CompareContactAttributes) branches true/false.
  Map<String, dynamic> _conditionTransitions(CallNode node) => {
    'NextAction': node.outputs['true'] ?? '',
    'Conditions': [
      if (node.outputs['false'] != null)
        {
          'Operator': 'Equals',
          'Operands': ['False'],
          'NextAction': node.outputs['false'],
        },
    ],
  };

  /// httpRequest (InvokeLambdaFunction) success/failure.
  Map<String, dynamic> _successFailureTransitions(CallNode node) => {
    'NextAction': node.outputs['success'] ?? '',
    'Errors': [
      if (node.outputs['failure'] != null)
        {'ErrorType': 'LambdaError', 'NextAction': node.outputs['failure']},
    ],
  };

  // ---------------------------------------------------------------------------
  // Small helpers.
  // ---------------------------------------------------------------------------

  /// Assemble one Connect Action. Empty transitions are omitted so terminal
  /// blocks (DisconnectParticipant) are clean.
  Map<String, dynamic> _action(
    CallNode node,
    String type,
    Map<String, dynamic> parameters,
    Map<String, dynamic> transitions,
  ) => {
    'Identifier': node.id,
    'Type': type,
    'Parameters': parameters,
    if (transitions.isNotEmpty) 'Transitions': transitions,
  };

  /// Resolve the prompt text for a node via its `promptId` config key, falling
  /// back to the node label so the block is never empty.
  String _promptText(CallSystemProject project, CallNode node) {
    final promptId = node.config['promptId'] as String?;
    if (promptId != null) {
      // Explicit [Prompt] type ties this exporter to the pbx_entities model.
      final Prompt? prompt = project.promptById(promptId);
      if (prompt != null && prompt.text.isNotEmpty) return prompt.text;
    }
    return node.label.isEmpty ? ' ' : node.label;
  }

  /// Sanitize a flow name into a safe file stem.
  String _safeFileName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final trimmed = cleaned.replaceAll(RegExp(r'^_|_$'), '');
    return trimmed.isEmpty ? 'flow' : trimmed;
  }

  @override
  List<String> notes(CallSystemProject project) {
    final caveats = <String>[
      'The exact Amazon Connect "Contact flow language" field names and block '
          'types should be validated against your current Connect instance '
          'before import; AWS evolves this schema and some Parameters/'
          'Transitions keys here are approximated.',
      'One .contactflow.json file is emitted per flow. Amazon Connect imports '
          'one Contact Flow per file.',
      'External dial / transfer-to-extension are mapped to TransferToFlow with '
          'the target number/extension as a parameter; in Connect, outbound '
          'bridging is typically a Quick Connect or queue, so wire the '
          'ContactFlowId/Quick Connect target after import.',
    ];

    // Surface node-type-specific impedance mismatches only when those node
    // types actually appear in the project, so the notes stay relevant.
    final usedTypes = <CallNodeType>{};
    for (final flow in project.flows) {
      for (final node in flow.nodes) {
        usedTypes.add(node.type);
      }
    }

    if (usedTypes.contains(CallNodeType.voicemail)) {
      caveats.add(
        'Voicemail nodes are emitted as a greeting message only. '
        'Native Connect voicemail requires the AWS Connect voicemail '
        'solution (Lambda + storage); wire it after import.',
      );
    }
    if (usedTypes.contains(CallNodeType.aiVoicebot)) {
      caveats.add(
        'AI voicebot nodes map to InvokeLambdaFunction carrying the '
        'configured goal; connect this to Amazon Lex / Bedrock for the '
        'conversational turn.',
      );
    }
    if (usedTypes.contains(CallNodeType.httpRequest)) {
      caveats.add(
        'HTTP request nodes map to InvokeLambdaFunction (Connect '
        'cannot call arbitrary HTTP endpoints directly); supply the Lambda '
        'ARN of an HTTP-proxy function.',
      );
    }
    if (usedTypes.contains(CallNodeType.record)) {
      caveats.add(
        'Record nodes are approximated with UpdateContactData; use '
        'the native "Set recording and analytics behavior" block to enable '
        'call recording in Connect.',
      );
    }
    if (usedTypes.contains(CallNodeType.playDirectory)) {
      caveats.add(
        'Dial-by-name directory has no native Connect block; the '
        'emitted GetParticipantInput placeholder must be built out manually.',
      );
    }
    if (usedTypes.contains(CallNodeType.ringGroup)) {
      caveats.add(
        'Ring groups are mapped to TransferContactToQueue (Connect '
        'routes by queue, not ad-hoc ring groups); create matching queues.',
      );
    }

    return caveats;
  }
}

/// Thin wrapper around a produced Connect Action (room to grow without
/// changing call sites).
class _MappedNode {
  final Map<String, dynamic> action;
  const _MappedNode(this.action);
}
