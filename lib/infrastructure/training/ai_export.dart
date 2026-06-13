// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/nexus_database.dart';

/// A STABLE rating handle derived from an assistant message's text. Content-based
/// (not positional) so a rating lines up with the exact reply regardless of
/// ordinal shifts (tool-only turns, image cards, reloads) — the UI and the
/// exporter compute it the same way, with no DB id threaded through the chat UI.
String aiMessageRef(String content) {
  final digest = sha1.convert(utf8.encode(content.trim())).toString();
  return 'h${digest.substring(0, 16)}';
}

/// Maps a training-sink conversation id to the AI it belongs to. Setup is hosted
/// by the Project Manager; Stories (discovery) and general chat by the Coordinator.
String aiKindForConversation(String conversationId) {
  if (conversationId.startsWith('setup:')) return 'setup';
  if (conversationId.startsWith('discovery:')) return 'stories';
  if (conversationId.startsWith('coordinator:')) return 'coordinator';
  return 'other';
}

/// The project_pk encoded in a conversation id (`setup:25` → 25), or null.
int? projectIdForConversation(String conversationId) {
  final parts = conversationId.split(':');
  if (parts.length < 2) return null;
  return int.tryParse(parts[1]);
}

/// The outcome of an export: where it was written + the JSON (for clipboard) +
/// a couple of counts for the confirmation UI.
class AiExportResult {
  const AiExportResult({
    required this.filePath,
    required this.json,
    required this.projectCount,
    required this.conversationCount,
    required this.ratingCount,
  });
  final String filePath;
  final String json;
  final int projectCount;
  final int conversationCount;
  final int ratingCount;
}

dynamic _decode(String? json) {
  if (json == null || json.trim().isEmpty) return null;
  try {
    return jsonDecode(json);
  } catch (_) {
    return null;
  }
}

/// Shape a rating DB row into the inline rating object attached to a message.
Map<String, dynamic> _ratingObj(Map<String, Object?> r) {
  final reasons = _decode(r['reasons_json'] as String?);
  final list = (reasons is Map && reasons['reasons'] is List)
      ? reasons['reasons'] as List
      : const [];
  final other = (reasons is Map) ? reasons['other'] : null;
  return {
    'stars': r['stars'],
    if (list.isNotEmpty) 'reasons': list,
    if (other != null && '$other'.trim().isNotEmpty) 'other': other,
    'ratedAt': r['updated_at'],
  };
}

/// Attach each message's rating inline (when one exists) onto the assistant
/// outputs in [messages], matching by the content-hash ref.
void _inlineRatings(
  List<dynamic> messages,
  Map<String, Map<String, Object?>> refMap,
) {
  if (refMap.isEmpty) return;
  for (final m in messages) {
    // Must be a string-keyed, dynamic-valued map so we can attach the rating
    // object (a Map) — a Map<String,String> would reject it.
    if (m is! Map<String, dynamic>) continue;
    if (m['role'] != 'assistant') continue;

    // 1) A spoken assistant reply — rated by its text.
    final content = m['content'];
    if (content is String && content.trim().isNotEmpty) {
      final rating = refMap[aiMessageRef(content)];
      if (rating != null) m['rating'] = _ratingObj(rating);
    }

    // 2) An ask_question tool call (Setup) — rated by the question it posed,
    //    which lives in the tool-call arguments, not the message content.
    final toolCalls = m['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final fn = tc['function'];
        if (fn is! Map || fn['name'] != 'ask_question') continue;
        final argsRaw = fn['arguments'];
        if (argsRaw is! String) continue;
        try {
          final decoded = jsonDecode(argsRaw);
          final q = decoded is Map ? decoded['question'] : null;
          if (q is String && q.trim().isNotEmpty) {
            final rating = refMap[aiMessageRef(q)];
            if (rating != null) tc['rating'] = _ratingObj(rating);
          }
        } catch (_) {}
      }
    }
  }
}

/// Build the export document for one AI ([aiKind] = 'setup' | 'stories') across
/// every project in [clientId], separated by project. Includes the captured rich
/// traces (tool calls + messages + responses + thoughts), their star ratings,
/// and the historical persisted text (setup transcript / chat history) so data
/// predating trace-capture is still covered.
Future<Map<String, dynamic>> buildAiExport(
  NexusDatabase db,
  int clientId,
  String aiKind,
  DateTime now,
) async {
  final projects = await db.getProjectsForClient(clientId);
  final pks = projects.map((pr) => pr.project_pk).toList();
  final traces = await db.getTrainingTraces(pks, aiKind: aiKind);
  // ALL ratings for these projects (not only ones with a captured trace) — a
  // rating is the training signal we must never drop.
  final ratings = await db.getAiRatingsForProjects(pks, aiKind: aiKind);

  final tracesByProject = <int, List<Map<String, Object?>>>{};
  for (final t in traces) {
    (tracesByProject[t['project_fk'] as int] ??= []).add(t);
  }
  final ratingsByProject = <int, List<Map<String, Object?>>>{};
  for (final r in ratings) {
    (ratingsByProject[r['project_fk'] as int] ??= []).add(r);
  }

  var conversationCount = 0;
  final projectsOut = <Map<String, dynamic>>[];
  for (final proj in projects) {
    final projRatings =
        ratingsByProject[proj.project_pk] ?? const <Map<String, Object?>>[];
    // Content-hash → rating, for inlining onto the matching assistant message.
    final refMap = <String, Map<String, Object?>>{
      for (final r in projRatings) r['message_ref'] as String: r,
    };

    final convs = <Map<String, dynamic>>[];
    for (final t
        in tracesByProject[proj.project_pk] ??
            const <Map<String, Object?>>[]) {
      conversationCount++;
      final messages = _decode(t['messages_json'] as String?);
      if (messages is List) _inlineRatings(messages, refMap);
      convs.add({
        'conversationId': t['conversation_id'],
        'updatedAt': t['updated_at'],
        'messages': messages ?? const [],
      });
    }

    final out = <String, dynamic>{
      'projectId': proj.project_pk,
      'projectName': proj.name,
      'conversations': convs,
      // Flat list of every rating for this project+AI, so they're always present
      // even if a rated message isn't matched inline.
      if (projRatings.isNotEmpty)
        'ratings': [
          for (final r in projRatings)
            {
              'conversationId': r['conversation_id'],
              'messageRef': r['message_ref'],
              ..._ratingObj(r),
            },
        ],
    };

    // Historical fallback (predates trace capture) — ratings inlined here too.
    if (aiKind == 'setup') {
      final transcript = _decode(proj.setupTranscriptJson);
      if (transcript is List && transcript.isNotEmpty) {
        _inlineRatings(transcript, refMap);
        out['setupTranscript'] = transcript;
      }
    } else if (aiKind == 'stories') {
      final sessions = await db.getChatSessionsForProject(proj.project_pk);
      final history = <Map<String, dynamic>>[];
      for (final s in sessions) {
        final msgs = await db.getChatMessagesForSession(s.session_pk);
        if (msgs.isEmpty) continue;
        final histMsgs = <dynamic>[
          for (final m in msgs)
            <String, dynamic>{'role': m.role, 'content': m.content},
        ];
        _inlineRatings(histMsgs, refMap);
        history.add({
          'sessionId': s.session_pk,
          'title': s.title,
          'messages': histMsgs,
        });
      }
      if (history.isNotEmpty) out['chatHistory'] = history;
    }

    projectsOut.add(out);
  }

  return {
    'aiKind': aiKind,
    'exportedAt': now.toIso8601String(),
    'clientId': clientId,
    'projectCount': projects.length,
    'conversationCount': conversationCount,
    'ratingCount': ratings.length,
    'projects': projectsOut,
  };
}

/// Build the export and write it to a timestamped JSON file in the OS Downloads
/// folder (falling back to app documents). Returns the path + the JSON string so
/// the caller can also offer "copy to clipboard".
Future<AiExportResult> exportAiTrainingData({
  required NexusDatabase db,
  required int clientId,
  required String aiKind,
  required DateTime now,
}) async {
  final data = await buildAiExport(db, clientId, aiKind, now);
  final json = const JsonEncoder.withIndent('  ').convert(data);

  Directory dir;
  try {
    dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final stamp = '${now.year}${_pad2(now.month)}${_pad2(now.day)}'
      '-${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
  final file = File(p.join(dir.path, 'nexus-$aiKind-ai-$stamp.json'));
  await file.writeAsString(json);

  return AiExportResult(
    filePath: file.path,
    json: json,
    projectCount: data['projectCount'] as int? ?? 0,
    conversationCount: data['conversationCount'] as int? ?? 0,
    ratingCount: data['ratingCount'] as int? ?? 0,
  );
}

String _pad2(int n) => n.toString().padLeft(2, '0');

// ── Worker (generalist) tool-call export — per project ──────────────────────

/// Flatten a worker trace into an ordered tool feed: each assistant tool call
/// (name + parsed args) paired with the result it produced.
List<Map<String, dynamic>> _extractToolFeed(List<dynamic> messages) {
  // tool_call_id → result text (from the `tool` role replies).
  final resultById = <String, String>{};
  for (final m in messages) {
    if (m is Map && m['role'] == 'tool') {
      final id = m['tool_call_id'];
      final content = m['content'];
      if (id is String && content is String) resultById[id] = content;
    }
  }
  final feed = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (m is! Map || m['role'] != 'assistant') continue;
    final tcs = m['tool_calls'];
    if (tcs is! List) continue;
    for (final tc in tcs) {
      if (tc is! Map) continue;
      final fn = tc['function'];
      if (fn is! Map) continue;
      final argsRaw = fn['arguments'];
      dynamic args = argsRaw;
      if (argsRaw is String) {
        try {
          args = jsonDecode(argsRaw);
        } catch (_) {
          args = argsRaw;
        }
      }
      final id = tc['id'];
      feed.add({
        'tool': fn['name'],
        'args': args,
        if (id is String && resultById.containsKey(id))
          'result': resultById[id],
      });
    }
  }
  return feed;
}

/// Build the worker tool-call export for ONE project: every orchestrated worker's
/// trace, flattened into per-task tool feeds (tool + args + result) plus the raw
/// trace. Per-project on purpose — across all projects this is a huge amount of
/// data.
Future<Map<String, dynamic>> buildWorkerToolExport(
  NexusDatabase db,
  int projectId,
  DateTime now,
) async {
  final proj = await db.getProjectById(projectId);
  final traces = await db.getTrainingTraces([projectId], aiKind: 'worker');
  var toolCallCount = 0;
  final tasks = <Map<String, dynamic>>[];
  for (final t in traces) {
    final convId = t['conversation_id'] as String? ?? '';
    final taskId = int.tryParse(convId.split(':').last);
    final messages = _decode(t['messages_json'] as String?);
    final feed = messages is List
        ? _extractToolFeed(messages)
        : <Map<String, dynamic>>[];
    toolCallCount += feed.length;
    tasks.add({
      'taskId': taskId,
      'updatedAt': t['updated_at'],
      'toolCalls': feed,
      'fullTrace': messages ?? const [],
    });
  }
  tasks.sort(
    (a, b) =>
        (a['taskId'] as int? ?? 0).compareTo(b['taskId'] as int? ?? 0),
  );
  return {
    'kind': 'worker_tool_calls',
    'projectId': projectId,
    'projectName': proj?.name,
    'exportedAt': now.toIso8601String(),
    'taskCount': tasks.length,
    'toolCallCount': toolCallCount,
    'tasks': tasks,
  };
}

/// The outcome of a worker export.
class WorkerExportResult {
  const WorkerExportResult({
    required this.filePath,
    required this.json,
    required this.taskCount,
    required this.toolCallCount,
  });
  final String filePath;
  final String json;
  final int taskCount;
  final int toolCallCount;
}

/// Build + write the worker tool-call JSON for [projectId] to Downloads.
Future<WorkerExportResult> exportWorkerToolData({
  required NexusDatabase db,
  required int projectId,
  required DateTime now,
}) async {
  final data = await buildWorkerToolExport(db, projectId, now);
  final json = const JsonEncoder.withIndent('  ').convert(data);

  Directory dir;
  try {
    dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  } catch (_) {
    dir = await getApplicationDocumentsDirectory();
  }
  final stamp = '${now.year}${_pad2(now.month)}${_pad2(now.day)}'
      '-${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
  final file = File(
    p.join(dir.path, 'nexus-worker-tools-p$projectId-$stamp.json'),
  );
  await file.writeAsString(json);

  return WorkerExportResult(
    filePath: file.path,
    json: json,
    taskCount: data['taskCount'] as int? ?? 0,
    toolCallCount: data['toolCallCount'] as int? ?? 0,
  );
}
