// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Sub-Tasks tab — real child tasks (task_parent_fk == this task), with creation.
class SubTasksTab extends ConsumerWidget {
  final int taskId;
  const SubTasksTab({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider);
    final tasksAsync = ref.watch(allTasksForProjectProvider(projectId));

    return tasksAsync.when(
      data: (all) {
        final children = all.where((t) => t.task_parent_fk == taskId).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Sub-Tasks',
                trailing: TextButton.icon(
                  onPressed: () => _addSubTask(context, ref, projectId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Sub-task'),
                ),
              ),
              Gap.md,
              if (children.isEmpty)
                const EmptyState(
                  icon: Icons.checklist_outlined,
                  title: 'No sub-tasks yet',
                  message: 'Break this task down into smaller pieces of work.',
                  compact: true,
                )
              else
                ...children.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: NexusCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  c.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '#${c.task_pk}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.nx.textFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          StatusChip(c.status, dense: true),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            tooltip: 'Open',
                            onPressed: () => ref
                                .read(selectedTaskIdNotifierProvider.notifier)
                                .selectTask(c.task_pk),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Future<void> _addSubTask(
    BuildContext context,
    WidgetRef ref,
    int projectId,
  ) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Sub-task'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    await ref
        .read(nexusDatabaseProvider)
        .createTaskInProject(
          projectPk: projectId,
          title: title,
          parentPk: taskId,
        );
  }
}
