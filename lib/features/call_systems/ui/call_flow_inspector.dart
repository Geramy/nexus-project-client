// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/nexus_ui.dart';
import '../call_system_editor.dart';
import '../call_system_providers.dart';
import '../model/call_node.dart';
import '../model/call_system_project.dart';
import 'node_visuals.dart';

/// Right-panel inspector for the selected call-flow node. Edits its label, its
/// spoken message (for prompt-bearing nodes), key parameters, and its output
/// connections; allows deleting non-entry nodes.
class CallFlowInspector extends ConsumerWidget {
  const CallFlowInspector({super.key, required this.projectId});
  final int projectId;

  static const _promptBearing = {
    CallNodeType.playPrompt,
    CallNodeType.menu,
    CallNodeType.gatherDigits,
    CallNodeType.gatherSpeech,
    CallNodeType.voicemail,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(callSystemProjectProvider(projectId));
    final selectedId = ref.watch(selectedCallNodeProvider(projectId));
    final flow = project.flows.isEmpty ? null : project.flows.first;
    final node = (selectedId == null || flow == null) ? null : flow.nodeById(selectedId);

    if (node == null) {
      return const EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Call Flow',
        message: 'Select a node on the canvas to edit its message and routing.',
      );
    }
    return _NodeInspectorBody(
      key: ValueKey(node.id),
      projectId: projectId,
      project: project,
      node: node,
      otherNodes: flow!.nodes.where((n) => n.id != node.id).toList(),
      isEntry: flow.entryNodeId == node.id,
    );
  }
}

class _NodeInspectorBody extends ConsumerStatefulWidget {
  const _NodeInspectorBody({
    super.key,
    required this.projectId,
    required this.project,
    required this.node,
    required this.otherNodes,
    required this.isEntry,
  });

  final int projectId;
  final CallSystemProject project;
  final CallNode node;
  final List<CallNode> otherNodes;
  final bool isEntry;

  @override
  ConsumerState<_NodeInspectorBody> createState() => _NodeInspectorBodyState();
}

class _NodeInspectorBodyState extends ConsumerState<_NodeInspectorBody> {
  late final TextEditingController _label =
      TextEditingController(text: widget.node.label);
  late final TextEditingController _message =
      TextEditingController(text: _initialMessage());
  late final TextEditingController _param =
      TextEditingController(text: _initialParam());

  CallSystemEditor get _editor =>
      ref.read(callSystemEditorProvider(widget.projectId));

  String _initialMessage() {
    final pid = widget.node.config['promptId'] as String?;
    if (pid == null) return '';
    return widget.project.promptById(pid)?.text ?? '';
  }

  String _initialParam() {
    final c = widget.node.config;
    return (c['number'] ?? c['extension'] ?? c['target'] ?? c['goal'] ?? '')
        .toString();
  }

  String? get _paramLabel => switch (widget.node.type) {
        CallNodeType.dial => 'Number to dial (E.164)',
        CallNodeType.transferToExtension => 'Extension number',
        CallNodeType.aiVoicebot => 'Voicebot goal / instructions',
        CallNodeType.gatherDigits ||
        CallNodeType.gatherSpeech =>
          'Store answer in variable',
        _ => null,
      };

  String get _paramKey => switch (widget.node.type) {
        CallNodeType.dial => 'number',
        CallNodeType.transferToExtension => 'extension',
        CallNodeType.aiVoicebot => 'goal',
        CallNodeType.gatherDigits ||
        CallNodeType.gatherSpeech =>
          'variable',
        _ => 'target',
      };

  @override
  void dispose() {
    _label.dispose();
    _message.dispose();
    _param.dispose();
    super.dispose();
  }

  void _commitLabel() =>
      _editor.updateNode(widget.node.copyWith(label: _label.text.trim()));

  void _commitParam() {
    final cfg = {...widget.node.config, _paramKey: _param.text.trim()};
    _editor.updateNode(widget.node.copyWith(config: cfg));
  }

  Future<void> _commitMessage() async {
    var pid = widget.node.config['promptId'] as String?;
    if (pid == null) {
      pid = 'prompt_${widget.node.id}';
      await _editor.updateNode(widget.node
          .copyWith(config: {...widget.node.config, 'promptId': pid}));
    }
    final existing = widget.project.promptById(pid);
    await _editor.upsertPrompt(
      (existing ?? Prompt(id: pid, voice: 'af_heart'))
          .copyWith(text: _message.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final color = colorForNodeType(widget.node.type, scheme);
    final showMessage = CallFlowInspector._promptBearing.contains(widget.node.type);
    final paramLabel = _paramLabel;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Icon(iconForNodeType(widget.node.type), color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(titleForNodeType(widget.node.type),
                  style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        Gap.lg,
        TextField(
          controller: _label,
          decoration: const InputDecoration(
              labelText: 'Label', border: OutlineInputBorder()),
          onEditingComplete: _commitLabel,
          onTapOutside: (_) => _commitLabel(),
        ),
        if (showMessage) ...[
          Gap.md,
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Spoken message',
              helperText: 'Synthesized with Omni TTS (kokoro).',
              border: OutlineInputBorder(),
            ),
            onEditingComplete: _commitMessage,
            onTapOutside: (_) => _commitMessage(),
          ),
        ],
        if (paramLabel != null) ...[
          Gap.md,
          TextField(
            controller: _param,
            decoration: InputDecoration(
                labelText: paramLabel, border: const OutlineInputBorder()),
            onEditingComplete: _commitParam,
            onTapOutside: (_) => _commitParam(),
          ),
        ],
        Gap.lg,
        Text('Routing', style: theme.textTheme.titleSmall),
        Gap.xs,
        Text('Where the call goes from each exit:',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: context.nx.textMuted)),
        Gap.sm,
        for (final port in widget.node.type.basePorts) _portRow(port, scheme),
        if (!widget.isEntry) ...[
          Gap.xl,
          OutlinedButton.icon(
            onPressed: () => _editor.removeNode(widget.node.id),
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text('Delete node', style: TextStyle(color: scheme.error)),
          ),
        ],
      ],
    );
  }

  Widget _portRow(String port, ColorScheme scheme) {
    final current = widget.node.outputs[port];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(port,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: DropdownButton<String?>(
                value: widget.otherNodes.any((n) => n.id == current)
                    ? current
                    : null,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                hint: const Text('— end / unset —', style: TextStyle(fontSize: 13)),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('— end / unset —')),
                  for (final n in widget.otherNodes)
                    DropdownMenuItem<String?>(
                        value: n.id,
                        child: Text(n.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => _editor.connect(widget.node.id, port, v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
