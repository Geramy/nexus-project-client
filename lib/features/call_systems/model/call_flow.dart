// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'call_node.dart';

/// A directed graph of [CallNode]s describing one call flow (an inbound IVR, an
/// outbound script, a voicebot conversation, a sub-routine, etc.). Edges are
/// stored as each node's `outputs` (port → target node id), so a whole flow is
/// one serializable object. Part of the portable call-system schema.
class CallFlow {
  final String id;
  final String name;
  final String? description;

  /// Id of the [CallNode] (type `entry`) where execution begins.
  final String entryNodeId;

  final List<CallNode> nodes;

  const CallFlow({
    required this.id,
    required this.name,
    required this.entryNodeId,
    this.nodes = const [],
    this.description,
  });

  CallNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  CallNode? get entryNode => nodeById(entryNodeId);

  CallFlow copyWith({
    String? name,
    String? description,
    String? entryNodeId,
    List<CallNode>? nodes,
  }) => CallFlow(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    entryNodeId: entryNodeId ?? this.entryNodeId,
    nodes: nodes ?? this.nodes,
  );

  /// Replace (or insert) a node by id.
  CallFlow upsertNode(CallNode node) {
    final next = [...nodes];
    final i = next.indexWhere((n) => n.id == node.id);
    if (i >= 0) {
      next[i] = node;
    } else {
      next.add(node);
    }
    return copyWith(nodes: next);
  }

  CallFlow removeNode(String nodeId) => copyWith(
    nodes: nodes
        .where((n) => n.id != nodeId)
        .map(
          (n) => n.outputs.containsValue(nodeId)
              // Drop edges that pointed at the removed node.
              ? n.copyWith(
                  outputs: {
                    for (final e in n.outputs.entries)
                      e.key: e.value == nodeId ? null : e.value,
                  },
                )
              : n,
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'entryNodeId': entryNodeId,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };

  factory CallFlow.fromJson(Map<String, dynamic> json) => CallFlow(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? 'Flow',
    description: json['description'] as String?,
    entryNodeId: (json['entryNodeId'] as String?) ?? '',
    nodes: ((json['nodes'] as List?) ?? const [])
        .map((e) => CallNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}
