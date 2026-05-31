// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../infrastructure/workspace/workspace_provider.dart';
import '../projects/workspace_nav.dart';
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

  Future<void> _complete() async {
    await ref.read(setupChatControllerProvider(_key)).completeSetup();
    if (!mounted) return;
    // Tasks were just generated, but nothing runs until orchestration is on.
    // If it's still off, surface a dialog that jumps straight to the toggle.
    final project =
        await ref.read(nexusDatabaseProvider).getProjectById(widget.projectId);
    if (!mounted) return;
    if (project?.orchestrationState != 'running') {
      await _showOrchestrationOffDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Plans ready — tasks created and orchestration is '
                'running.')),
      );
    }
  }

  Future<void> _showOrchestrationOffDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.motion_photos_off_outlined),
        title: const Text('Orchestration is off'),
        content: const Text(
            'Your plans are ready and tasks have been created, but no agents '
            'will start working until you turn orchestration on.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Nudge the workspace to surface the Overview tab (Start button).
              ref.read(requestOverviewTabProvider.notifier).state++;
            },
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Turn on orchestration'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the action bar tracks the shared interview's busy + phase state.
    final busy = ref.watch(
        setupChatControllerProvider(_key).select((c) => c.busy));
    final refining = ref.watch(
        setupChatControllerProvider(_key).select((c) => c.refining));
    return Column(
      children: [
        _ActionBar(
          busy: busy,
          refining: refining,
          onSkip: _skip,
          onFinalize: _finalize,
          onComplete: _complete,
        ),
        const Divider(height: 1),
        Expanded(child: TagBoardView(projectPk: widget.projectId)),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.refining,
    required this.onSkip,
    required this.onFinalize,
    required this.onComplete,
  });

  final bool busy;
  final bool refining;
  final VoidCallback onSkip;
  final VoidCallback onFinalize;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.checklist_rtl, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(refining ? 'Refining Plans' : 'Project Setup',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (!refining) ...[
            TextButton(
                onPressed: busy ? null : onSkip, child: const Text('Skip')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy ? null : onFinalize,
              icon: const Icon(Icons.flag_outlined, size: 16),
              label: const Text('Finalize & generate plans'),
            ),
          ] else
            FilledButton.icon(
              onPressed: busy ? null : onComplete,
              icon: const Icon(Icons.task_alt, size: 16),
              label: const Text('Done refining → tasks'),
            ),
        ],
      ),
    );
  }
}
