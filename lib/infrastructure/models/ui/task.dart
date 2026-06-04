// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

class Task {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final int tokenCost;
  final double usdCost;
  final String? mastermindPersonaId;
  final List<String> subAgentIds;
  final String? parentId; // For task tree hierarchy
  final List<String> childIds; // Sub-tasks

  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.tokenCost = 0,
    this.usdCost = 0.0,
    this.mastermindPersonaId,
    this.subAgentIds = const [],
    this.parentId,
    this.childIds = const [],
  });

  Task copyWith({
    String? title,
    String? description,
    String? status,
    String? priority,
    int? tokenCost,
    double? usdCost,
    String? mastermindPersonaId,
    List<String>? subAgentIds,
    String? parentId,
    List<String>? childIds,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      tokenCost: tokenCost ?? this.tokenCost,
      usdCost: usdCost ?? this.usdCost,
      mastermindPersonaId: mastermindPersonaId ?? this.mastermindPersonaId,
      subAgentIds: subAgentIds ?? this.subAgentIds,
      parentId: parentId ?? this.parentId,
      childIds: childIds ?? this.childIds,
    );
  }
}
