// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// `POST /v1/chat/completions` — non-streaming and streaming with tool call assembly.

import 'dart:async';
import 'dart:convert';

import '../lemonade_client.dart';
import '../sse/tool_call_assembler.dart';
import '../types/chat_request.dart';
import '../types/chat_response.dart';

class ChatEndpoint {
  final LemonadeApiClient _client;
  const ChatEndpoint(this._client);

  /// `POST /v1/chat/completions` with `stream: false`.
  Future<ChatCompletion> create(
    ChatCompletionRequest request, {
    Duration? timeout,
  }) async {
    if (request.stream)
      throw StreamProtocolException(
        'create() requires stream:false; use stream() instead.',
      );
    final body = await _client.postJson(
      _client.apiUriFor('/chat/completions'),
      request.toWireJson(),
      timeout: timeout,
    );
    return ChatCompletion.fromJson(body);
  }

  /// `POST /v1/chat/completions` with `stream: true`.
  /// Yields [ChatContentDelta], [ChatToolCallDelta], and finally [ChatStreamFinish].
  Stream<ChatStreamEvent> stream(ChatCompletionRequest request) async* {
    final req = ChatCompletionRequest(
      model: request.model,
      messages: request.messages,
      tools: request.tools,
      stream: true,
      temperature: request.temperature,
      topP: request.topP,
      topK: request.topK,
      repeatPenalty: request.repeatPenalty,
      maxCompletionTokens: request.maxCompletionTokens,
      stop: request.stop,
      enableThinking: request.enableThinking,
      extra: request.extra,
    );

    final assembler = ToolCallAssembler();
    final contentBuf = StringBuffer();
    String? finishReason;
    var sawFinish = false;

    final sse = _client.streamSseFromJsonPost(
      _client.apiUriFor('/chat/completions'),
      req.toWireJson(),
    );

    await for (final event in sse) {
      final data = event.data.trim();
      if (data.isEmpty || data == '[DONE]') break;

      Map<String, dynamic> chunk;
      try {
        final decoded = jsonDecode(data);
        if (decoded is! Map<String, dynamic>) continue;
        chunk = decoded;
      } catch (_) {
        continue; // Skip malformed chunks.
      }

      final choices = chunk['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final first = choices.first;
      if (first is! Map<String, dynamic>) continue;

      final delta = first['delta'];
      if (delta is Map<String, dynamic>) {
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          contentBuf.write(content);
          yield ChatContentDelta(content);
        }
        if (delta['tool_calls'] is List) {
          final touched = assembler.observe(delta);
          if (touched.isNotEmpty) yield ChatToolCallDelta(touched);
        }
      }

      final fr = first['finish_reason'];
      if (fr is String) {
        finishReason = fr;
        sawFinish = true;
      }
    }

    yield ChatStreamFinish(
      finishReason: finishReason ?? (sawFinish ? null : 'stop'),
      toolCalls: assembler.finalize(),
      contentSoFar: contentBuf.toString(),
    );
  }
}

class StreamProtocolException implements Exception {
  final String message;
  const StreamProtocolException(this.message);
  @override
  String toString() => message;
}
