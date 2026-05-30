// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// WebSocket log stream subscription for Lemonade servers.
/// Ported from ~/IdeaProjects/lemonade_mobile/lib/api/realtime/logs_socket.dart

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Subscribes to the Lemonade server's `/logs/stream` WebSocket.
///
/// Discover the WebSocket port via [health] (`websocket_port` field), then
/// pass it into [connect]. After connection, [subscribe] with optional [afterSeq] to
/// resume from a known sequence number; the server first sends a `logs.snapshot` of
/// up to 5000 entries, then live `logs.entry` messages.
class LogsSocket {
  final String serverUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _events = StreamController<LogsEvent>.broadcast();

  LogsSocket(this.serverUrl);

  Stream<LogsEvent> get events => _events.stream;

  /// Emit only while the controller is still open. Closing the WebSocket fires
  /// onDone asynchronously, which could otherwise add to a closed controller
  /// ("Cannot add new events after calling close").
  void _emit(LogsEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> connect({required int port}) async {
    final apiUri = Uri.parse(serverUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final uri = Uri(
      scheme: scheme,
      host: apiUri.host,
      port: port,
      path: '/logs/stream',
    );

    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (err) => _emit(LogsError(err.toString())),
      onDone: () => _emit(const LogsDisconnected()),
    );
  }

  /// Subscribe to log stream. Pass [afterSeq] to resume after a known seq number.
  void subscribe({int? afterSeq}) {
    _send({'type': 'logs.subscribe', 'after_seq': afterSeq});
  }

  Future<void> close() async {
    // Cancel the subscription first so onDone/onError can't fire into a
    // controller we're about to close.
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }

  void _send(Map<String, dynamic> message) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(message));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;
    switch (type) {
      case 'logs.snapshot':
        final entries = msg['entries'];
        if (entries is List) {
          _emit(LogsSnapshot([
            for (final e in entries.whereType<Map<String, dynamic>>())
              LogEntry.fromJson(e),
          ]));
        }
        break;
      case 'logs.entry':
        final entry = msg['entry'];
        if (entry is Map<String, dynamic>) {
          _emit(LogsLive(LogEntry.fromJson(entry)));
        }
        break;
      case 'error':
        _emit(LogsError(msg['message']?.toString() ?? 'Unknown error'));
        break;
    }
  }
}

class LogEntry {
  final int seq;
  final String timestamp;
  final String severity; // Trace | Debug | Info | Warning | Error | Fatal
  final String tag;
  final String line;

  LogEntry({
    required this.seq,
    required this.timestamp,
    required this.severity,
    required this.tag,
    required this.line,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        timestamp: json['timestamp'] as String? ?? '',
        severity: json['severity'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        line: json['line'] as String? ?? '',
      );
}

sealed class LogsEvent {
  const LogsEvent();
}

class LogsSnapshot extends LogsEvent {
  final List<LogEntry> entries;
  const LogsSnapshot(this.entries);
}

class LogsLive extends LogsEvent {
  final LogEntry entry;
  const LogsLive(this.entry);
}

class LogsError extends LogsEvent {
  final String message;
  const LogsError(this.message);
}

class LogsDisconnected extends LogsEvent {
  const LogsDisconnected();
}
