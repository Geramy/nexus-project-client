// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// OpenAI tool_call as it appears on assistant messages.

class ToolCall {
  final String id;
  final String name;
  final String argumentsJson;

  const ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  Map<String, dynamic> toWireJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': argumentsJson},
  };

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final fn = json['function'] as Map<String, dynamic>? ?? const {};
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: fn['name'] as String? ?? '',
      argumentsJson: fn['arguments'] as String? ?? '{}',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCall && id == other.id && name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

/// In-progress tool call as observed during streaming.
class PartialToolCall {
  final int index;
  final String? id;
  final String? name;
  final String argumentsAccum;

  const PartialToolCall({
    required this.index,
    this.id,
    this.name,
    required this.argumentsAccum,
  });
}
