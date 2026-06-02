// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'call_flow.dart';
import 'pbx_entities.dart';

/// Sub-categories of the IVR / Call-Systems project type. Each tunes which nodes
/// and entities are emphasized and which compliance rules apply (outbound types
/// carry TCPA/consent/DNC obligations).
enum CallSystemSubCategory {
  inboundIvr, // auto-attendant / menu routing
  outboundCampaign, // reminders, notifications, outbound AI
  aiVoicebot, // conversational virtual agent
  callCenter, // ACD / queues / agents
  appointmentReminder,
  survey, // IVR data collection
}

CallSystemSubCategory subCategoryFromKey(String k) =>
    CallSystemSubCategory.values.firstWhere((s) => s.name == k,
        orElse: () => CallSystemSubCategory.inboundIvr);

/// Whether outbound calling is part of this sub-category (drives the compliance
/// surface the builder enforces/warns on).
bool subCategoryIsOutbound(CallSystemSubCategory s) =>
    s == CallSystemSubCategory.outboundCampaign ||
    s == CallSystemSubCategory.appointmentReminder ||
    s == CallSystemSubCategory.survey;

/// A reusable spoken prompt: the author's [text], the kokoro [voice] it's
/// synthesized with, and the path to the generated audio asset (relative to the
/// exported bundle). Recorded prompts set [audioAssetPath] with empty [text].
class Prompt {
  final String id;
  final String text;
  final String? voice; // kokoro voice id, e.g. 'af_heart'
  final String? audioAssetPath; // e.g. 'audio/welcome.wav'

  const Prompt({
    required this.id,
    this.text = '',
    this.voice,
    this.audioAssetPath,
  });

  Prompt copyWith({String? text, String? voice, String? audioAssetPath}) =>
      Prompt(
        id: id,
        text: text ?? this.text,
        voice: voice ?? this.voice,
        audioAssetPath: audioAssetPath ?? this.audioAssetPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'voice': voice,
        'audioAssetPath': audioAssetPath,
      };

  factory Prompt.fromJson(Map<String, dynamic> j) => Prompt(
        id: j['id'] as String,
        text: (j['text'] as String?) ?? '',
        voice: j['voice'] as String?,
        audioAssetPath: j['audioAssetPath'] as String?,
      );
}

/// The PORTABLE call-system project: the single source of truth a user can
/// export wholesale (this JSON + the referenced audio files) and deploy on ANY
/// backend, or deploy to the Nexus-managed runtime for "full AI mode". The
/// builder edits this model; per-provider exporters and the managed runtime read
/// it. Nothing here is provider-specific.
class CallSystemProject {
  /// Bump when the schema changes incompatibly.
  static const int schemaVersion = 1;

  final String name;
  final CallSystemSubCategory subCategory;

  /// 'regular' | 'advanced' — presentation only; same model underneath.
  final String experienceMode;

  // ── Standard PBX entities ──────────────────────────────────────────
  final List<Did> dids;
  final List<Extension> extensions;
  final List<RingGroup> ringGroups;
  final List<PickupGroup> pickupGroups;
  final List<ParkGroup> parkGroups;
  final List<CallQueue> queues;
  final List<VoicemailBox> voicemailBoxes;
  final List<TimeCondition> timeConditions;

  // ── Flows, prompts, variables ──────────────────────────────────────
  final List<CallFlow> flows;
  final List<Prompt> prompts;

  /// Default flow variables (e.g. company name, hours text) available to nodes.
  final Map<String, dynamic> variables;

  const CallSystemProject({
    required this.name,
    this.subCategory = CallSystemSubCategory.inboundIvr,
    this.experienceMode = 'regular',
    this.dids = const [],
    this.extensions = const [],
    this.ringGroups = const [],
    this.pickupGroups = const [],
    this.parkGroups = const [],
    this.queues = const [],
    this.voicemailBoxes = const [],
    this.timeConditions = const [],
    this.flows = const [],
    this.prompts = const [],
    this.variables = const {},
  });

  bool get isOutbound => subCategoryIsOutbound(subCategory);

  Prompt? promptById(String id) {
    for (final p in prompts) {
      if (p.id == id) return p;
    }
    return null;
  }

  CallFlow? flowById(String id) {
    for (final f in flows) {
      if (f.id == id) return f;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'name': name,
        'subCategory': subCategory.name,
        'experienceMode': experienceMode,
        'dids': dids.map((e) => e.toJson()).toList(),
        'extensions': extensions.map((e) => e.toJson()).toList(),
        'ringGroups': ringGroups.map((e) => e.toJson()).toList(),
        'pickupGroups': pickupGroups.map((e) => e.toJson()).toList(),
        'parkGroups': parkGroups.map((e) => e.toJson()).toList(),
        'queues': queues.map((e) => e.toJson()).toList(),
        'voicemailBoxes': voicemailBoxes.map((e) => e.toJson()).toList(),
        'timeConditions': timeConditions.map((e) => e.toJson()).toList(),
        'flows': flows.map((e) => e.toJson()).toList(),
        'prompts': prompts.map((e) => e.toJson()).toList(),
        'variables': variables,
      };

  factory CallSystemProject.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) from) =>
        ((j[key] as List?) ?? const [])
            .map((e) => from(Map<String, dynamic>.from(e as Map)))
            .toList();
    return CallSystemProject(
      name: (j['name'] as String?) ?? 'Call System',
      subCategory: subCategoryFromKey((j['subCategory'] as String?) ?? 'inboundIvr'),
      experienceMode: (j['experienceMode'] as String?) ?? 'regular',
      dids: list('dids', Did.fromJson),
      extensions: list('extensions', Extension.fromJson),
      ringGroups: list('ringGroups', RingGroup.fromJson),
      pickupGroups: list('pickupGroups', PickupGroup.fromJson),
      parkGroups: list('parkGroups', ParkGroup.fromJson),
      queues: list('queues', CallQueue.fromJson),
      voicemailBoxes: list('voicemailBoxes', VoicemailBox.fromJson),
      timeConditions: list('timeConditions', TimeCondition.fromJson),
      flows: list('flows', CallFlow.fromJson),
      prompts: list('prompts', Prompt.fromJson),
      variables:
          Map<String, dynamic>.from(j['variables'] as Map? ?? const {}),
    );
  }
}
