// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'chat_message.dart';

class ChatCompletionRequest {
  final String model;
  final List<Map<String, dynamic>>
  messages; // wire-format maps directly (avoiding ApiChatMessage conversion overhead in hot path)
  final List<Map<String, dynamic>>?
  tools; // tool definitions as wire-format maps
  final bool stream;

  // Standard sampling params.
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? repeatPenalty;
  final int? maxCompletionTokens;
  final List<String>? stop;

  // Lemonade extension.
  final bool? enableThinking;

  /// Free-form additional fields merged into the body last (override anything above).
  final Map<String, dynamic>? extra;

  ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.tools,
    this.stream = false,
    this.temperature,
    this.topP,
    this.topK,
    this.repeatPenalty,
    this.maxCompletionTokens,
    this.stop,
    this.enableThinking,
    this.extra,
  });

  /// Build a wire-format body map.
  Map<String, dynamic> toWireJson() {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': stream,
    };
    if (tools != null && tools!.isNotEmpty) body['tools'] = tools;
    if (temperature != null) body['temperature'] = temperature!;
    if (topP != null) body['top_p'] = topP!;
    if (topK != null) body['top_k'] = topK!;
    if (repeatPenalty != null) body['repeat_penalty'] = repeatPenalty!;
    if (maxCompletionTokens != null)
      body['max_completion_tokens'] = maxCompletionTokens!;
    if (stop != null && stop!.isNotEmpty) body['stop'] = stop!;
    if (enableThinking != null) body['enable_thinking'] = enableThinking!;
    if (extra != null) body.addAll(extra!);
    return body;
  }

  /// Convert a list of ApiChatMessage to wire-format maps. Convenience helper.
  static List<Map<String, dynamic>> apiMessagesToWire(
    List<ApiChatMessage> messages,
  ) => messages.map((m) => m.toWireJson()).toList();
}
