// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../infrastructure/workspace/workspace_provider.dart';
import 'setup_chat_controller.dart';
import 'tag_board_view.dart';
import 'workspace_tag_observer.dart';

/// The always-available Project Setup tab. The Tag Board fills this center pane;
/// the AI interview runs as a chat in the MainShell right outer panel
/// ([SetupInterviewPanel]), sharing state via [setupChatControllerProvider].
class SetupTab extends ConsumerStatefulWidget {
  const SetupTab({super.key, required this.projectId, required this.clientId});

  final int projectId;
  final int clientId;

  @override
  ConsumerState<SetupTab> createState() => _SetupTabState();
}

class _SetupTabState extends ConsumerState<SetupTab> {
  ({int projectId, int clientId}) get _key =>
      (projectId: widget.projectId, clientId: widget.clientId);

  @override
  void initState() {
    super.initState();
    _observeWorkspace();
  }

  /// Best-effort: turn real manifests (pubspec/Cargo/etc.) into accepted,
  /// workspace-sourced tags so the board reflects what's actually in the tree.
  Future<void> _observeWorkspace() async {
    try {
      final workspace =
          await ref.read(workspaceFsProvider(widget.projectId).future);
      final observer = WorkspaceTagObserver(
        workspace: workspace,
        db: ref.read(nexusDatabaseProvider),
      );
      await observer.scan(widget.projectId);
    } catch (_) {
      // Workspace may not exist yet — ignore.
    }
  }

  Future<void> _finalize() async {
    final controller = ref.read(setupChatControllerProvider(_key));
    try {
      final result = await controller.finalize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result), duration: const Duration(seconds: 4)),
        );
      }
    } catch (_) {
      if (mounted && controller.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.error!)),
        );
      }
    }
  }

  Future<void> _skip() async {
    await ref.read(setupChatControllerProvider(_key)).skip();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Setup skipped — you can finish it any time.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the action bar's busy state tracks the shared interview.
    final busy = ref.watch(
        setupChatControllerProvider(_key).select((c) => c.busy));
    return Column(
      children: [
        _ActionBar(busy: busy, onSkip: _skip, onFinalize: _finalize),
        const Divider(height: 1),
        Expanded(child: TagBoardView(projectPk: widget.projectId)),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.onSkip,
    required this.onFinalize,
  });

  final bool busy;
  final VoidCallback onSkip;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.checklist_rtl, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Project Setup',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          TextButton(onPressed: busy ? null : onSkip, child: const Text('Skip')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy ? null : onFinalize,
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: const Text('Finalize & generate plans'),
          ),
        ],
      ),
    );
  }
}
