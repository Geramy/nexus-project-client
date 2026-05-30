// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'tool_call.dart';

enum WireRole { system, user, assistant, tool }

/// A piece of multi-modal user content.
class ApiContentPart {
  final String type; // 'text' | 'image_url' | 'input_audio'
  final String? text;
  final String? imageUrl;
  final String? audioBase64;
  final String? audioFormat;

  const ApiContentPart._({required this.type, this.text, this.imageUrl, this.audioBase64, this.audioFormat});

  const ApiContentPart.text(String t) : this._(type: 'text', text: t);
  const ApiContentPart.imageUrl(String url) : this._(type: 'image_url', imageUrl: url);
  const ApiContentPart.audio(String base64, {required String format})
      : this._(type: 'input_audio', audioBase64: base64, audioFormat: format);

  Map<String, dynamic> toWireJson() {
    switch (type) {
      case 'text':
        return {'type': 'text', 'text': text ?? ''};
      case 'image_url':
        return {'type': 'image_url', 'image_url': {'url': imageUrl ?? ''}};
      case 'input_audio':
        return {'type': 'input_audio', 'input_audio': {'data': audioBase64 ?? '', 'format': audioFormat ?? 'wav'}};
      default:
        return {'type': type};
    }
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is ApiContentPart && type == other.type && text == other.text;
  @override
  int get hashCode => type.hashCode ^ text.hashCode;
}

class ApiChatMessage {
  final WireRole role;
  final String? content;
  final List<ApiContentPart>? contentParts;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final String? name;

  const ApiChatMessage({required this.role, this.content, this.contentParts, this.toolCalls, this.toolCallId, this.name});

  ApiChatMessage.system(String text) : this(role: WireRole.system, content: text);
  ApiChatMessage.user(String text) : this(role: WireRole.user, content: text);
  ApiChatMessage.userParts(List<ApiContentPart> parts) : this(role: WireRole.user, contentParts: parts);
  ApiChatMessage.assistant(String text) : this(role: WireRole.assistant, content: text);

  ApiChatMessage.assistantToolCalls(List<ToolCall> calls, {String? content})
      : this(role: WireRole.assistant, content: content, toolCalls: calls);

  ApiChatMessage.tool(String result, {required String toolCallId, String? name})
      : this(role: WireRole.tool, content: result, toolCallId: toolCallId, name: name);

  Map<String, dynamic> toWireJson() {
    final json = <String, dynamic>{'role': _roleString(role)};
    if (contentParts != null) {
      json['content'] = contentParts!.map((p) => p.toWireJson()).toList();
    } else {
      json['content'] = content;
    }
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      json['tool_calls'] = toolCalls!.map((c) => c.toWireJson()).toList();
    }
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    if (name != null) json['name'] = name;
    return json;
  }

  static String _roleString(WireRole r) {
    switch (r) {
      case WireRole.system:
        return 'system';
      case WireRole.user:
        return 'user';
      case WireRole.assistant:
        return 'assistant';
      case WireRole.tool:
        return 'tool';
    }
  }

  static ApiChatMessage _parseRole(String s) {
    switch (s) {
      case 'system':
        return const ApiChatMessage(role: WireRole.system);
      case 'user':
        return const ApiChatMessage(role: WireRole.user);
      case 'assistant':
        return const ApiChatMessage(role: WireRole.assistant);
      case 'tool':
        return const ApiChatMessage(role: WireRole.tool);
      default:
        return const ApiChatMessage(role: WireRole.user);
    }
  }

  factory ApiChatMessage.fromJson(Map<String, dynamic> json) {
    final role = _parseRole(json['role'] as String? ?? 'user');
    final rawContent = json['content'];
    String? contentString;
    if (rawContent is String) {
      contentString = rawContent;
    } else if (rawContent is List) {
      // Multi-part content — not round-tripped here.
    }

    final calls = json['tool_calls'] is List
        ? (json['tool_calls'] as List).whereType<Map<String, dynamic>>().map(ToolCall.fromJson).toList()
        : null;

    return ApiChatMessage(role: role.role!, content: contentString, toolCalls: calls);
  }
}
