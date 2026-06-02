// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// The canonical, PROVIDER-AGNOSTIC call-flow node set. Phone systems share a
/// standard: every major backend reduces to this same set of primitives. The
/// only real difference between providers is declarative (Twilio Studio/TwiML)
/// vs. imperative (Telnyx Call Control, Asterisk dialplan/AGI), which the
/// per-provider exporters absorb — the builder and runtime only ever speak this
/// model. (Cross-checked against Twilio Studio widgets, Telnyx Call Control,
/// Asterisk IVR, and Amazon Connect contact flows in the IVR research.)
enum CallNodeType {
  /// The flow's single entry point (where an inbound call or outbound session
  /// begins). One per flow.
  entry,

  /// Play a [prompt] — synthesized TTS (kokoro) or a recorded audio asset.
  playPrompt,

  /// IVR menu: play a prompt, gather one or more DTMF digits, branch per key.
  /// Outputs are keyed by the digit(s) plus `timeout` and `invalid`.
  menu,

  /// Collect DTMF input into a variable (e.g. an account or PIN number).
  gatherDigits,

  /// Collect spoken input (Whisper STT) into a variable.
  gatherSpeech,

  /// A conversational AI turn: stream caller audio → STT → LLM → TTS (kokoro),
  /// with barge-in/interruption. The voicebot path (Twilio ConversationRelay /
  /// Media Streams / Telnyx media streaming style) wired to Omni.
  aiVoicebot,

  /// Dial / bridge to an external phone number (PSTN or SIP).
  dial,

  /// Transfer to an internal [Extension].
  transferToExtension,

  /// Ring a [RingGroup] (ring-all / hunt / round-robin, etc.).
  ringGroup,

  /// Place the caller in an ACD [Queue].
  queue,

  /// Send the caller to a [VoicemailBox] to leave a message.
  voicemail,

  /// Branch on a [TimeCondition] (business hours / holidays).
  schedule,

  /// Branch on a variable/expression. Outputs `true` / `false` (or per-case).
  condition,

  /// Assign a value to a flow variable.
  setVariable,

  /// Call out to an HTTP endpoint (webhook / API) and capture the response.
  httpRequest,

  /// Record the call (subject to recording-consent rules per jurisdiction).
  record,

  /// Dial-by-name directory lookup.
  playDirectory,

  /// End the call.
  hangup,

  /// Jump into another [CallFlow] as a sub-routine.
  subFlow,
}

extension CallNodeTypeX on CallNodeType {
  String get key => name;

  /// The canonical OUTPUT port names for this node type — the transitions the
  /// editor draws and the exporters map. Menus add a port per configured digit
  /// at runtime (see [CallNode.outputs]); these are the always-present ports.
  List<String> get basePorts => switch (this) {
        CallNodeType.entry => const ['next'],
        CallNodeType.playPrompt => const ['next'],
        CallNodeType.menu => const ['timeout', 'invalid'],
        CallNodeType.gatherDigits => const ['next', 'timeout'],
        CallNodeType.gatherSpeech => const ['next', 'timeout', 'nomatch'],
        CallNodeType.aiVoicebot => const ['next', 'transfer', 'hangup'],
        CallNodeType.dial => const ['answered', 'noanswer', 'busy', 'failed'],
        CallNodeType.transferToExtension =>
          const ['answered', 'noanswer', 'busy'],
        CallNodeType.ringGroup => const ['answered', 'noanswer'],
        CallNodeType.queue => const ['answered', 'timeout', 'empty'],
        CallNodeType.voicemail => const ['done'],
        CallNodeType.schedule => const ['open', 'closed', 'holiday'],
        CallNodeType.condition => const ['true', 'false'],
        CallNodeType.setVariable => const ['next'],
        CallNodeType.httpRequest => const ['success', 'failure'],
        CallNodeType.record => const ['next'],
        CallNodeType.playDirectory => const ['matched', 'nomatch'],
        CallNodeType.hangup => const [],
        CallNodeType.subFlow => const ['returned'],
      };

  /// True for node types only meaningful to expert/Advanced users; the Regular
  /// mode hides these behind AI assistance or presets.
  bool get isAdvanced => switch (this) {
        CallNodeType.condition ||
        CallNodeType.setVariable ||
        CallNodeType.httpRequest ||
        CallNodeType.subFlow =>
          true,
        _ => false,
      };
}

CallNodeType callNodeTypeFromKey(String key) =>
    CallNodeType.values.firstWhere((t) => t.key == key,
        orElse: () => CallNodeType.playPrompt);

/// Approval state of a node. AI-generated nodes start [proposed] (ghosted on the
/// canvas, awaiting the user's ✓); manually-added nodes are [approved]. Legacy
/// nodes without a stored status deserialize to [approved].
enum NodeStatus { proposed, approved }

NodeStatus nodeStatusFromKey(String? key) =>
    key == 'proposed' ? NodeStatus.proposed : NodeStatus.approved;

/// A single node in a [CallFlow]. Type-specific parameters live in [config]
/// (e.g. `promptId`, `variable`, `target`, `digits`) so the model stays flat and
/// serializable; typed editors read/write those keys. [outputs] maps each output
/// port name to the id of the next node (null = unconnected) — this IS the edge
/// set, kept on the node so the graph round-trips as one object.
class CallNode {
  final String id;
  final CallNodeType type;
  final String label;

  /// Canvas position (logical units).
  final double x;
  final double y;

  final Map<String, dynamic> config;
  final Map<String, String?> outputs;

  /// Approval state — proposed nodes (AI-generated) await the user's ✓.
  final NodeStatus status;

  const CallNode({
    required this.id,
    required this.type,
    required this.label,
    this.x = 0,
    this.y = 0,
    this.config = const {},
    this.outputs = const {},
    this.status = NodeStatus.approved,
  });

  bool get isProposed => status == NodeStatus.proposed;

  CallNode copyWith({
    String? label,
    double? x,
    double? y,
    Map<String, dynamic>? config,
    Map<String, String?>? outputs,
    NodeStatus? status,
  }) =>
      CallNode(
        id: id,
        type: type,
        label: label ?? this.label,
        x: x ?? this.x,
        y: y ?? this.y,
        config: config ?? this.config,
        outputs: outputs ?? this.outputs,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.key,
        'label': label,
        'x': x,
        'y': y,
        'config': config,
        'outputs': outputs,
        'status': status.name,
      };

  factory CallNode.fromJson(Map<String, dynamic> json) => CallNode(
        id: json['id'] as String,
        type: callNodeTypeFromKey(json['type'] as String),
        label: (json['label'] as String?) ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        config: Map<String, dynamic>.from(json['config'] as Map? ?? const {}),
        outputs: (json['outputs'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as String?),
            ) ??
            const {},
        status: nodeStatusFromKey(json['status'] as String?),
      );
}
