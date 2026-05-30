// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// OpenAI function-calling tool schema.

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final List<String>? requiresLabels;
  final List<String>? requiresLlmLabels;
  final bool isAppControl;

  const ToolDefinition({required this.name, required this.description, required this.parameters, this.requiresLabels, this.requiresLlmLabels, this.isAppControl = false});

  Map<String, dynamic> toWireJson() => {
        'type': 'function',
        'function': {'name': name, 'description': description, 'parameters': parameters},
      };
}
