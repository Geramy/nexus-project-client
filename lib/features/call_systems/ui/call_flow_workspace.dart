// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../infrastructure/workspace/workspace.dart';
import '../../../infrastructure/workspace/workspace_provider.dart';
import '../../../shared/ui/nexus_ui.dart';
import '../call_system_ai_service.dart';
import '../call_system_editor.dart';
import '../call_system_providers.dart';
import '../export/export_writer.dart';
import '../model/call_node.dart';
import '../model/call_system_project.dart';
import 'ai_assist_dialog.dart';
import 'call_flow_canvas.dart';
import 'export_dialog.dart';
import 'node_visuals.dart';

/// Builder's Regular(false)/Advanced(true) toggle — gates the node palette.
final callBuilderAdvancedProvider = StateProvider.family<bool, int>(
  (ref, projectId) => false,
);

/// Center-pane workspace for the IVR / Call Systems project type: a toolbar
/// (add-node palette, Regular/Advanced toggle) over the visual call-flow canvas.
class CallFlowWorkspace extends ConsumerWidget {
  const CallFlowWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider);
    final project = ref.watch(callSystemProjectProvider(projectId));
    final advanced = ref.watch(callBuilderAdvancedProvider(projectId));
    final theme = Theme.of(context);

    final paletteTypes = [
      ...kRegularPaletteNodes,
      if (advanced) ...kAdvancedPaletteNodes,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.account_tree_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Call Flow · ${project.name}',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Text(
                'Advanced',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.nx.textMuted,
                ),
              ),
              Switch(
                value: advanced,
                onChanged: (v) =>
                    ref
                            .read(
                              callBuilderAdvancedProvider(projectId).notifier,
                            )
                            .state =
                        v,
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => showCallAiAssistDialog(context, projectId),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('AI assist'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () =>
                    _downloadWorkspaceZip(context, ref, projectId, project),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => showCallExportDialog(context, project),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Export'),
              ),
              const SizedBox(width: AppSpacing.sm),
              PopupMenuButton<CallNodeType>(
                tooltip: 'Add a step',
                onSelected: (type) {
                  final flow = project.flows.isEmpty
                      ? null
                      : project.flows.first;
                  final n = (flow?.nodes.length ?? 0);
                  // Cascade new nodes so they don't stack exactly.
                  final x = 340.0 + (n % 4) * 36.0;
                  final y = 120.0 + (n % 8) * 30.0;
                  ref
                      .read(callSystemEditorProvider(projectId))
                      .addNode(type, x, y);
                },
                itemBuilder: (context) => [
                  for (final t in paletteTypes)
                    PopupMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(
                            iconForNodeType(t),
                            size: 18,
                            color: colorForNodeType(t, theme.colorScheme),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(titleForNodeType(t)),
                        ],
                      ),
                    ),
                ],
                child: FilledButton.icon(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    disabledBackgroundColor: theme.colorScheme.primary,
                    disabledForegroundColor: theme.colorScheme.onPrimary,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add step'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _ReviewBanner(projectId: projectId),
        Expanded(child: CallFlowCanvas(projectId: projectId)),
      ],
    );
  }
}

/// Snapshot the current call flow into the project workspace as portable JSON,
/// then zip the ENTIRE workspace (our git-backed sandbox: flow JSON, synthesized
/// prompt audio, plans, everything) into a single `.zip` and reveal it. This is
/// the "download my whole project" action surfaced right on the call tree.
Future<void> _downloadWorkspaceZip(
  BuildContext context,
  WidgetRef ref,
  int projectId,
  CallSystemProject project,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Packaging project…')));
  try {
    final ws = await ref.read(workspaceFsProvider(projectId).future);
    // Drop any synthesized audio no prompt references anymore so the export is
    // clean (no orphaned clips from renamed/regenerated prompts).
    await ref.read(callSystemAiServiceProvider(projectId)).pruneOrphanAudio();
    // Persist the latest flow as portable JSON into the repo so the zip is a
    // complete, self-describing snapshot (the tree references repo-relative
    // audio paths already written under call-system/audio/).
    await ws.writeBytes(
      '/call-system/call_system.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(project.toJson())),
    );
    final zip = await exportWorkspaceZip(ws, project.name);
    await revealInFileManager(zip.zipPath);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Exported ${zip.fileCount} file(s) '
          '(${formatBytes(zip.bytes)}) → ${zip.zipPath}',
        ),
      ),
    );
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

/// Shown when AI-proposed nodes are awaiting the user's approval. The tree is the
/// review surface: approve nodes in place, or accept the lot here.
class _ReviewBanner extends ConsumerWidget {
  const _ReviewBanner({required this.projectId});
  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(callSystemProjectProvider(projectId));
    final flow = project.flows.isEmpty ? null : project.flows.first;
    final pending = flow?.nodes.where((n) => n.isProposed).length ?? 0;
    if (pending == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: const Color(0xFFD9920B).withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.rate_review_outlined,
            size: 18,
            color: Color(0xFFB47708),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$pending ${pending == 1 ? 'step is' : 'steps are'} proposed — '
              'review on the tree (▶ listen, ✓ approve, ✗ reject) or accept all.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(callSystemEditorProvider(projectId)).approveAll(),
            child: const Text('Approve all'),
          ),
        ],
      ),
    );
  }
}
