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
    final content = m['content'];
    if (content is! String || content.trim().isEmpty) continue;
    final rating = refMap[aiMessageRef(content)];
    if (rating != null) m['rating'] = _ratingObj(rating);
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
