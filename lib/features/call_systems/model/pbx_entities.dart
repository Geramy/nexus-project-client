// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// The standard PBX building blocks every phone system shares — extensions,
/// ring/pickup/park groups, queues, voicemail, time conditions, DIDs and trunks.
/// These are provider-agnostic: each maps onto voip.ms, Twilio, Telnyx, Asterisk
/// (FreePBX), Amazon Connect, etc. via the per-provider exporters. Plain,
/// serializable value objects; part of the portable call-system schema.
library;

/// Helper for round-tripping a list of JSON-able entities.
List<Map<String, dynamic>> entitiesToJson(List<dynamic> items) =>
    items.map((e) => (e as dynamic).toJson() as Map<String, dynamic>).toList();

/// A user/endpoint on the system. Dialable internally by [number]; can register
/// a SIP device and own a [voicemailBoxId].
class Extension {
  final String id;
  final String number; // internal dial number, e.g. "101"
  final String name;
  final String? voicemailBoxId;

  /// Optional SIP credentials/labels for Advanced users. The managed runtime
  /// provisions these; self-serve users fill them for their own PBX.
  final String? sipUsername;
  final int ringSeconds;

  const Extension({
    required this.id,
    required this.number,
    required this.name,
    this.voicemailBoxId,
    this.sipUsername,
    this.ringSeconds = 20,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'name': name,
        'voicemailBoxId': voicemailBoxId,
        'sipUsername': sipUsername,
        'ringSeconds': ringSeconds,
      };

  factory Extension.fromJson(Map<String, dynamic> j) => Extension(
        id: j['id'] as String,
        number: (j['number'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        voicemailBoxId: j['voicemailBoxId'] as String?,
        sipUsername: j['sipUsername'] as String?,
        ringSeconds: (j['ringSeconds'] as num?)?.toInt() ?? 20,
      );
}

/// How a [RingGroup] distributes a call across its members. A "hunt group" is a
/// ring group with a sequential strategy — modeled as a strategy, not a separate
/// type, matching how FreePBX/Asterisk treat it.
enum RingStrategy {
  ringAll, // ring every member at once
  hunt, // sequential, fixed order (classic hunt group)
  memoryHunt, // sequential, accumulating
  roundRobin, // rotate the starting member
  fewestRecent, // least-recently-answered first
  random,
}

RingStrategy ringStrategyFromKey(String k) =>
    RingStrategy.values.firstWhere((s) => s.name == k,
        orElse: () => RingStrategy.ringAll);

/// A group of extensions rung together by a [RingStrategy]. Falls back to
/// [failoverVoicemailBoxId] (or a flow node) on no-answer.
class RingGroup {
  final String id;
  final String name;
  final String? number;
  final List<String> extensionIds;
  final RingStrategy strategy;
  final int ringSeconds;
  final String? failoverVoicemailBoxId;

  const RingGroup({
    required this.id,
    required this.name,
    this.number,
    this.extensionIds = const [],
    this.strategy = RingStrategy.ringAll,
    this.ringSeconds = 20,
    this.failoverVoicemailBoxId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'number': number,
        'extensionIds': extensionIds,
        'strategy': strategy.name,
        'ringSeconds': ringSeconds,
        'failoverVoicemailBoxId': failoverVoicemailBoxId,
      };

  factory RingGroup.fromJson(Map<String, dynamic> j) => RingGroup(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        number: j['number'] as String?,
        extensionIds: ((j['extensionIds'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        strategy: ringStrategyFromKey((j['strategy'] as String?) ?? 'ringAll'),
        ringSeconds: (j['ringSeconds'] as num?)?.toInt() ?? 20,
        failoverVoicemailBoxId: j['failoverVoicemailBoxId'] as String?,
      );
}

/// A call-pickup permission group: any member may answer another member's
/// ringing call (e.g. `*8` directed pickup).
class PickupGroup {
  final String id;
  final String name;
  final List<String> memberExtensionIds;

  const PickupGroup({
    required this.id,
    required this.name,
    this.memberExtensionIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'memberExtensionIds': memberExtensionIds,
      };

  factory PickupGroup.fromJson(Map<String, dynamic> j) => PickupGroup(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        memberExtensionIds: ((j['memberExtensionIds'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );
}

/// Call park / hold orbit: a set of numbered slots a call can be parked in and
/// retrieved from elsewhere. (The "hold group" concept.)
class ParkGroup {
  final String id;
  final String name;
  final int slots;
  final int timeoutSeconds;

  const ParkGroup({
    required this.id,
    required this.name,
    this.slots = 10,
    this.timeoutSeconds = 120,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slots': slots,
        'timeoutSeconds': timeoutSeconds,
      };

  factory ParkGroup.fromJson(Map<String, dynamic> j) => ParkGroup(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        slots: (j['slots'] as num?)?.toInt() ?? 10,
        timeoutSeconds: (j['timeoutSeconds'] as num?)?.toInt() ?? 120,
      );
}

/// An ACD (automatic call distribution) queue: callers wait with music-on-hold
/// while agents are rung by a [RingStrategy].
class CallQueue {
  final String id;
  final String name;
  final String? number;
  final List<String> agentExtensionIds;
  final RingStrategy strategy;
  final String? musicOnHoldPromptId;
  final int maxWaitSeconds;

  const CallQueue({
    required this.id,
    required this.name,
    this.number,
    this.agentExtensionIds = const [],
    this.strategy = RingStrategy.fewestRecent,
    this.musicOnHoldPromptId,
    this.maxWaitSeconds = 300,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'number': number,
        'agentExtensionIds': agentExtensionIds,
        'strategy': strategy.name,
        'musicOnHoldPromptId': musicOnHoldPromptId,
        'maxWaitSeconds': maxWaitSeconds,
      };

  factory CallQueue.fromJson(Map<String, dynamic> j) => CallQueue(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        number: j['number'] as String?,
        agentExtensionIds: ((j['agentExtensionIds'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        strategy:
            ringStrategyFromKey((j['strategy'] as String?) ?? 'fewestRecent'),
        musicOnHoldPromptId: j['musicOnHoldPromptId'] as String?,
        maxWaitSeconds: (j['maxWaitSeconds'] as num?)?.toInt() ?? 300,
      );
}

/// A voicemail mailbox with a greeting prompt and optional email delivery.
class VoicemailBox {
  final String id;
  final String name;
  final String? mailboxNumber;
  final String? greetingPromptId;
  final String? emailTo;

  const VoicemailBox({
    required this.id,
    required this.name,
    this.mailboxNumber,
    this.greetingPromptId,
    this.emailTo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mailboxNumber': mailboxNumber,
        'greetingPromptId': greetingPromptId,
        'emailTo': emailTo,
      };

  factory VoicemailBox.fromJson(Map<String, dynamic> j) => VoicemailBox(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        mailboxNumber: j['mailboxNumber'] as String?,
        greetingPromptId: j['greetingPromptId'] as String?,
        emailTo: j['emailTo'] as String?,
      );
}

/// One open-hours window within a [TimeCondition]. Days are 1=Mon..7=Sun;
/// times are minutes-from-midnight in the system [TimeCondition.timezone].
class TimeRange {
  final List<int> days;
  final int startMinute;
  final int endMinute;

  const TimeRange({
    this.days = const [1, 2, 3, 4, 5],
    this.startMinute = 9 * 60,
    this.endMinute = 17 * 60,
  });

  Map<String, dynamic> toJson() =>
      {'days': days, 'startMinute': startMinute, 'endMinute': endMinute};

  factory TimeRange.fromJson(Map<String, dynamic> j) => TimeRange(
        days: ((j['days'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        startMinute: (j['startMinute'] as num?)?.toInt() ?? 540,
        endMinute: (j['endMinute'] as num?)?.toInt() ?? 1020,
      );
}

/// Business-hours / holiday schedule the `schedule` node branches on.
class TimeCondition {
  final String id;
  final String name;
  final String timezone; // IANA tz, e.g. "America/New_York"
  final List<TimeRange> openRanges;
  final List<String> holidayDates; // ISO yyyy-MM-dd

  const TimeCondition({
    required this.id,
    required this.name,
    this.timezone = 'America/New_York',
    this.openRanges = const [],
    this.holidayDates = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'timezone': timezone,
        'openRanges': openRanges.map((r) => r.toJson()).toList(),
        'holidayDates': holidayDates,
      };

  factory TimeCondition.fromJson(Map<String, dynamic> j) => TimeCondition(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        timezone: (j['timezone'] as String?) ?? 'America/New_York',
        openRanges: ((j['openRanges'] as List?) ?? const [])
            .map((e) => TimeRange.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        holidayDates: ((j['holidayDates'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );
}

/// An inbound phone number (DID). Routes incoming calls to a [flowId] (or a
/// direct entity). On the managed plan this is provisioned through the Router
/// from voip.ms; self-serve users map their own number.
class Did {
  final String id;
  final String e164; // +15551234567
  final String? label;
  final String? flowId; // entry flow for inbound calls
  final bool managed; // provisioned by Nexus (vs the user's own number)

  const Did({
    required this.id,
    required this.e164,
    this.label,
    this.flowId,
    this.managed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'e164': e164,
        'label': label,
        'flowId': flowId,
        'managed': managed,
      };

  factory Did.fromJson(Map<String, dynamic> j) => Did(
        id: j['id'] as String,
        e164: (j['e164'] as String?) ?? '',
        label: j['label'] as String?,
        flowId: j['flowId'] as String?,
        managed: (j['managed'] as bool?) ?? false,
      );
}
