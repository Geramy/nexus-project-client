// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/providers/database_provider.dart';
import 'call_system_providers.dart';
import 'model/call_flow.dart';
import 'model/call_node.dart';
import 'model/call_system_project.dart';

/// Id of the node selected on the canvas (drives the inspector). Per project.
final selectedCallNodeProvider = StateProvider.family<String?, int>(
  (ref, projectId) => null,
);

/// Read-modify-write editor for a project's [CallSystemProject]. The DB is the
/// single source of truth: every mutation reads the current decoded document,
/// transforms it, and upserts the JSON — the reactive [callSystemProjectProvider]
/// then rebuilds the canvas. Operates on the first ("Main") flow for now.
final callSystemEditorProvider = Provider.family<CallSystemEditor, int>((
  ref,
  projectId,
) {
  return CallSystemEditor(ref, projectId);
});

class CallSystemEditor {
  CallSystemEditor(this._ref, this.projectId);
  final Ref _ref;
  final int projectId;

  CallSystemProject get current =>
      _ref.read(callSystemProjectProvider(projectId));

  Future<void> _commit(CallSystemProject p) => _ref
      .read(nexusDatabaseProvider)
      .upsertCallSystem(projectId, jsonEncode(p.toJson()));

  /// The active flow (Main) and a setter that replaces it within the project.
  CallFlow? get _flow => current.flows.isEmpty ? null : current.flows.first;

  Future<void> _replaceFlow(CallFlow flow) async {
    final p = current;
    final flows = [...p.flows];
    final i = flows.indexWhere((f) => f.id == flow.id);
    if (i >= 0) {
      flows[i] = flow;
    } else {
      flows.add(flow);
    }
    await _commit(_copyWithFlows(p, flows));
  }

  CallSystemProject _copyWithFlows(CallSystemProject p, List<CallFlow> flows) =>
      CallSystemProject(
        name: p.name,
        subCategory: p.subCategory,
        experienceMode: p.experienceMode,
        dids: p.dids,
        extensions: p.extensions,
        ringGroups: p.ringGroups,
        pickupGroups: p.pickupGroups,
        parkGroups: p.parkGroups,
        queues: p.queues,
        voicemailBoxes: p.voicemailBoxes,
        timeConditions: p.timeConditions,
        flows: flows,
        prompts: p.prompts,
        variables: p.variables,
      );

  // ── Node ops ────────────────────────────────────────────────────────

  Future<void> moveNode(String nodeId, double x, double y) async {
    final flow = _flow;
    final node = flow?.nodeById(nodeId);
    if (flow == null || node == null) return;
    await _replaceFlow(flow.upsertNode(node.copyWith(x: x, y: y)));
  }

  Future<void> updateNode(CallNode node) async {
    final flow = _flow;
    if (flow == null) return;
    await _replaceFlow(flow.upsertNode(node));
  }

  /// Add a new node of [type] at ([x],[y]) and select it. Returns its id.
  Future<String> addNode(CallNodeType type, double x, double y) async {
    final flow = _flow;
    if (flow == null) return '';
    final id =
        'node_${type.key}_${flow.nodes.length + 1}_${x.toInt()}${y.toInt()}';
    final node = CallNode(
      id: id,
      type: type,
      label: _defaultLabel(type),
      x: x,
      y: y,
    );
    await _replaceFlow(flow.upsertNode(node));
    _ref.read(selectedCallNodeProvider(projectId).notifier).state = id;
    return id;
  }

  Future<void> removeNode(String nodeId) async {
    final flow = _flow;
    if (flow == null) return;
    if (flow.entryNodeId == nodeId) return; // never delete the entry node
    await _replaceFlow(flow.removeNode(nodeId));
    final sel = _ref.read(selectedCallNodeProvider(projectId));
    if (sel == nodeId) {
      _ref.read(selectedCallNodeProvider(projectId).notifier).state = null;
    }
  }

  // ── Approval (AI-proposed nodes) ────────────────────────────────────

  /// Mark a proposed node approved (it goes solid on the canvas).
  Future<void> approveNode(String nodeId) async {
    final flow = _flow;
    final node = flow?.nodeById(nodeId);
    if (flow == null || node == null || !node.isProposed) return;
    await _replaceFlow(
      flow.upsertNode(node.copyWith(status: NodeStatus.approved)),
    );
  }

  /// Approve every proposed node in the active flow.
  Future<void> approveAll() async {
    final flow = _flow;
    if (flow == null) return;
    var next = flow;
    for (final n in flow.nodes.where((n) => n.isProposed)) {
      next = next.upsertNode(n.copyWith(status: NodeStatus.approved));
    }
    await _replaceFlow(next);
  }

  /// Reject (delete) a proposed node.
  Future<void> rejectNode(String nodeId) => removeNode(nodeId);

  int get pendingCount => _flow?.nodes.where((n) => n.isProposed).length ?? 0;

  /// Wire [fromNodeId]'s [port] to [targetId] (null disconnects).
  Future<void> connect(String fromNodeId, String port, String? targetId) async {
    final flow = _flow;
    final node = flow?.nodeById(fromNodeId);
    if (flow == null || node == null) return;
    await _replaceFlow(
      flow.upsertNode(
        node.copyWith(outputs: {...node.outputs, port: targetId}),
      ),
    );
  }

  // ── Prompt ops ──────────────────────────────────────────────────────

  Future<void> upsertPrompt(Prompt prompt) async {
    final p = current;
    final prompts = [...p.prompts];
    final i = prompts.indexWhere((x) => x.id == prompt.id);
    if (i >= 0) {
      prompts[i] = prompt;
    } else {
      prompts.add(prompt);
    }
    await _commit(_copyWithPrompts(p, prompts));
  }

  CallSystemProject _copyWithPrompts(
    CallSystemProject p,
    List<Prompt> prompts,
  ) => CallSystemProject(
    name: p.name,
    subCategory: p.subCategory,
    experienceMode: p.experienceMode,
    dids: p.dids,
    extensions: p.extensions,
    ringGroups: p.ringGroups,
    pickupGroups: p.pickupGroups,
    parkGroups: p.parkGroups,
    queues: p.queues,
    voicemailBoxes: p.voicemailBoxes,
    timeConditions: p.timeConditions,
    flows: p.flows,
    prompts: prompts,
    variables: p.variables,
  );

  /// Replace the whole document (used by AI-assist / import).
  Future<void> replaceProject(CallSystemProject project) => _commit(project);

  static String _defaultLabel(CallNodeType type) => switch (type) {
    CallNodeType.entry => 'Call starts',
    CallNodeType.playPrompt => 'Play message',
    CallNodeType.menu => 'Menu',
    CallNodeType.gatherDigits => 'Get digits',
    CallNodeType.gatherSpeech => 'Get speech',
    CallNodeType.aiVoicebot => 'AI voicebot',
    CallNodeType.dial => 'Dial number',
    CallNodeType.transferToExtension => 'Transfer',
    CallNodeType.ringGroup => 'Ring group',
    CallNodeType.queue => 'Queue',
    CallNodeType.voicemail => 'Voicemail',
    CallNodeType.schedule => 'Business hours',
    CallNodeType.condition => 'Condition',
    CallNodeType.setVariable => 'Set variable',
    CallNodeType.httpRequest => 'API request',
    CallNodeType.record => 'Record',
    CallNodeType.playDirectory => 'Dial by name',
    CallNodeType.hangup => 'End call',
    CallNodeType.subFlow => 'Sub-flow',
  };
}
