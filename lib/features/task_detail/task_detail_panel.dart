// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show Task;

import '../../shared/ui/nexus_ui.dart';
import '../projects/types/project_type.dart';
import '../projects/types/project_type_providers.dart';
import 'tabs/overview_tab.dart';
import 'tabs/sub_tasks_tab.dart';
import 'tabs/git_changes_tab.dart';
import 'tabs/agent_work_tab.dart';
import 'tabs/builds_ci_tab.dart';
import 'tabs/audit_tab.dart';

/// Task Detail Panel — loads the real task from the DB and hosts its tabs.
class TaskDetailPanel extends ConsumerWidget {
  final int? taskId;

  const TaskDetailPanel({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (taskId == null) {
      return const Center(child: Text('Select a task'));
    }

    final projectId = ref.watch(currentProjectIdProvider);
    final tasksAsync = ref.watch(allTasksForProjectProvider(projectId));
    final connectionMode = ref.watch(connectionModeNotifierProvider);

    return tasksAsync.when(
      data: (tasks) {
        Task? task;
        for (final t in tasks) {
          if (t.task_pk == taskId) {
            task = t;
            break;
          }
        }
        if (task == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'Task "$taskId" is not in the current project.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.nx.textMuted),
              ),
            ),
          );
        }
        final t = task;
        // Gate software-only tabs by the project type's capabilities, so
        // non-software projects (e.g. IVR / Call Systems) don't show Git/CI.
        final type = ref.watch(projectTypeProvider(t.task_project_fk));
        final showGit = type.has(ProjectCapability.git);
        final showBuild =
            type.has(ProjectCapability.build) || type.has(ProjectCapability.ci);
        final tabSpecs = <({String label, Widget view})>[
          (
            label: 'Overview',
            view: OverviewTab(
              key: ValueKey('ov-${t.task_pk}'),
              taskId: t.task_pk,
            ),
          ),
          (
            label: 'Sub-Tasks',
            view: SubTasksTab(
              key: ValueKey('st-${t.task_pk}'),
              taskId: t.task_pk,
            ),
          ),
          if (showGit)
            (
              label: 'Git Changes',
              view: GitChangesTab(
                key: ValueKey('gc-${t.task_pk}'),
                taskId: t.task_pk,
                projectId: t.task_project_fk,
                workBranch: t.workBranch,
              ),
            ),
          (
            label: 'Agent Work',
            view: AgentWorkTab(
              key: ValueKey('aw-${t.task_pk}'),
              taskId: t.task_pk,
            ),
          ),
          if (showBuild)
            (
              label: 'Builds & CI',
              view: BuildsCiTab(
                key: ValueKey('ci-${t.task_pk}'),
                projectPk: t.task_project_fk,
                taskId: t.task_pk,
              ),
            ),
          (
            label: 'Audit',
            view: AuditTab(
              key: ValueKey('au-${t.task_pk}'),
              taskId: t.task_pk,
              projectId: t.task_project_fk,
              workBranch: t.workBranch,
            ),
          ),
        ];
        return DefaultTabController(
          length: tabSpecs.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, t, connectionMode),
              TabBar(
                isScrollable: true,
                // Pin tabs to the left edge (x=0) instead of the default
                // scrollable leading offset, so they don't appear to drift right.
                tabAlignment: TabAlignment.start,
                tabs: [for (final s in tabSpecs) Tab(text: s.label)],
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: TabBarView(children: [for (final s in tabSpecs) s.view]),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  ChipIntent _priorityIntent(String p) {
    switch (p.toUpperCase()) {
      case 'HIGH':
        return ChipIntent.danger;
      case 'LOW':
        return ChipIntent.neutral;
      default:
        return ChipIntent.warning;
    }
  }

  Widget _buildHeader(BuildContext context, Task task, String mode) {
    final nx = context.nx;
    final cost = task.usdCost > 0
        ? '${task.tokenCost} tokens • \$${task.usdCost.toStringAsFixed(2)}'
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: nx.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${task.task_pk}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              StatusChip(
                task.priority,
                intent: _priorityIntent(task.priority),
                dense: true,
              ),
              StatusChip(task.status, intent: ChipIntent.accent, dense: true),
              if (task.dueDate != null)
                Text(
                  'Due ${_fmt(task.dueDate!)}',
                  style: TextStyle(fontSize: 12, color: nx.textMuted),
                ),
              if (cost != null)
                Text(cost, style: TextStyle(fontSize: 12, color: nx.textFaint)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            task.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          Gap.xs,
          Text(
            mode == 'local' ? '● Local • Full power' : '● Remote (Routed)',
            style: TextStyle(
              fontSize: 11,
              color: mode == 'local' ? nx.success : nx.info,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
