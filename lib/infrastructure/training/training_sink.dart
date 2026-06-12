// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Default endpoint of the local Nexus Training Studio's HTTPS API. The studio
/// runs on the same machine; data never leaves localhost.
const String kDefaultTrainingSinkUrl = 'https://localhost:8443/training-data';

/// Best-effort, fire-and-forget shipper of validated agent conversation traces
/// to the local Training Studio, so the fine-tuning dataset grows as the app is
/// used. Failures are swallowed — this never blocks or breaks a turn. Accepts
/// the studio's self-signed TLS cert (localhost only).
class TrainingSink {
  final bool enabled;
  final String url;

  const TrainingSink({this.enabled = true, this.url = kDefaultTrainingSinkUrl});

  /// Ship one conversation [messages] (OpenAI shape: system/user/assistant/tool
  /// with tool_calls) under a stable [conversationId]; the studio keeps the
  /// LONGEST trace per id, so re-posting a growing conversation collapses to its
  /// final, complete form (no prefix spam).
  void post(String conversationId, List<Map<String, dynamic>> messages) {
    if (!enabled || messages.isEmpty) return;
    // Fire-and-forget; never await in the turn's hot path.
    unawaited(_send(conversationId, messages));
  }

  Future<void> _send(
      String conversationId, List<Map<String, dynamic>> messages) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        // localhost self-signed cert from the studio — trust it.
        ..badCertificateCallback = (cert, host, port) => host == 'localhost';
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'conversation_id': conversationId,
        'messages': messages,
      })));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      await resp.drain();
    } catch (_) {
      // Studio not running / unreachable — that's fine, just skip. Traces are
      // still captured locally (Account → Export Tracking), so this upload is
      // optional. Log ONCE per session instead of spamming a line every turn.
      if (!_warnedUnreachable) {
        _warnedUnreachable = true;
        debugPrint(
          'TrainingSink: local Training Studio not reachable — skipping uploads '
          'this session (conversation traces are still saved locally for export).',
        );
      }
    } finally {
      client?.close(force: true);
    }
  }

  /// One-shot guard so an unreachable studio doesn't log on every turn.
  static bool _warnedUnreachable = false;
}

/// Default sink → on, pointed at the local studio. (Toggle/URL can later be
/// surfaced in settings; default-on is safe because it's localhost-only.)
final trainingSinkProvider = Provider<TrainingSink>(
  (ref) => const TrainingSink(),
);
