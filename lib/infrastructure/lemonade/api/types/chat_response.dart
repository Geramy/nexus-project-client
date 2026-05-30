// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'chat_message.dart';
import 'tool_call.dart';

/// Non-streaming response shape.
class ChatCompletion {
  final String id;
  final String model;
  final ApiChatMessage message;
  final String? finishReason; // 'stop' | 'tool_calls' | 'length' | null
  final ChatUsage? usage;

  const ChatCompletion({required this.id, required this.model, required this.message, this.finishReason, this.usage});

  factory ChatCompletion.fromJson(Map<String, dynamic> json) {
    final choices = (json['choices'] as List?) ?? <dynamic>[];
    final first = choices.isNotEmpty ? choices.first as Map<String, dynamic>? : null;
    final msgJson = (first?['message'])?.cast<String, dynamic>() ?? const {};
    return ChatCompletion(
      id: json['id'] as String? ?? '',
      model: json['model'] as String? ?? '',
      message: ApiChatMessage.fromJson(msgJson),
      finishReason: first?['finish_reason'] as String?,
      usage: (json['usage'] is Map) ? ChatUsage.fromJson((json['usage'] as Map).cast<String, dynamic>()) : null,
    );
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is ChatCompletion && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

class ChatUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  const ChatUsage({required this.promptTokens, required this.completionTokens, required this.totalTokens});
  factory ChatUsage.fromJson(Map<String, dynamic> json) => ChatUsage(
        promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
        totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
      );
}

/// Streaming chunk events emitted by [ChatEndpoint.stream].
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

class ChatContentDelta extends ChatStreamEvent {
  final String text;
  const ChatContentDelta(this.text);
}

class ChatToolCallDelta extends ChatStreamEvent {
  final List<PartialToolCall> partials;
  const ChatToolCallDelta(this.partials);
}

/// Stream finished. Provides fully-assembled [toolCalls] and the finish reason.
class ChatStreamFinish extends ChatStreamEvent {
  final String? finishReason; // 'stop' | 'tool_calls' | 'length'
  final List<ToolCall> toolCalls;
  final String contentSoFar;

  const ChatStreamFinish({required this.finishReason, required this.toolCalls, required this.contentSoFar});
}
