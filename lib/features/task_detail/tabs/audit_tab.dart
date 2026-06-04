// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/git_engine_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Audit tab — a real, live, chronological audit trail assembled from the
/// actual events recorded for THIS task. There is no audit/event table, so the
/// trail is aggregated on the fly from three live sources:
///   1. Task lifecycle (created / execution status / submission) from the DB.
///   2. Build / CI runs gating this task (streamed from the DB).
///   3. Git commits from the project's libgit2 engine.
class AuditTab extends ConsumerWidget {
  final int taskId;
  final int projectId;
  final String? workBranch;

  const AuditTab({
    super.key,
    required this.taskId,
    required this.projectId,
    this.workBranch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);

    // Source 1: the task list (AsyncValue) — re-renders when the row changes.
    final tasksAsync = ref.watch(allTasksForProjectProvider(projectId));

    // Source 3 trigger: bump on any workspace mutation (commit/create/delete).
    final wsRevision = ref.watch(workspaceRevisionProvider(projectId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Audit Trail for this Task',
            subtitle:
                'A live, chronological record assembled from task lifecycle, build/CI runs, and git commits.',
          ),
          Gap.md,

          // Source 2 (CI/build) is a stream; nest the git FutureBuilder inside so
          // the whole composed list re-renders whenever any source updates.
          StreamBuilder<List<CiRun>>(
            stream: db.watchCiRunsForProject(projectId),
            builder: (context, ciSnapshot) {
              final ciRuns = (ciSnapshot.data ?? const <CiRun>[])
                  .where((r) => r.task_fk == taskId)
                  .toList();

              return FutureBuilder<List<_AuditEvent>>(
                // Key the future by the workspace revision so it re-fetches the
                // git log whenever the repo changes.
                key: ValueKey('audit-git-$projectId-$wsRevision'),
                future: _loadGitEvents(ref),
                builder: (context, gitSnapshot) {
                  final events = <_AuditEvent>[];

                  // Source 1: task lifecycle.
                  tasksAsync.whenData((tasks) {
                    Task? task;
                    for (final t in tasks) {
                      if (t.task_pk == taskId) {
                        task = t;
                        break;
                      }
                    }
                    if (task != null) {
                      events.addAll(_taskEvents(task));
                    }
                  });

                  // Source 2: build / CI events.
                  for (final run in ciRuns) {
                    events.addAll(_ciEvents(run));
                  }

                  // Source 3: git commits (zero events on error / no repo).
                  if (gitSnapshot.hasData) {
                    events.addAll(gitSnapshot.data!);
                  }

                  final loading =
                      tasksAsync.isLoading ||
                      ciSnapshot.connectionState == ConnectionState.waiting ||
                      gitSnapshot.connectionState == ConnectionState.waiting;

                  if (events.isEmpty) {
                    if (loading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (tasksAsync.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Text(
                          'Failed to load audit trail: ${tasksAsync.error}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.nx.danger,
                          ),
                        ),
                      );
                    }
                    return const EmptyState(
                      icon: Icons.history_toggle_off,
                      title: 'No recorded events',
                      message: 'No recorded events for this task yet.',
                      compact: true,
                    );
                  }

                  // Newest first.
                  events.sort((a, b) => b.time.compareTo(a.time));

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: events.length,
                    itemBuilder: (context, index) =>
                        _AuditEventTile(event: events[index]),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Source builders
  // ---------------------------------------------------------------------------

  List<_AuditEvent> _taskEvents(Task task) {
    final events = <_AuditEvent>[
      _AuditEvent(
        time: task.createdAt,
        type: 'human',
        title: 'Task created: ${task.title}',
        actor: 'System',
      ),
      _AuditEvent(
        time: task.updatedAt,
        type: 'delegation',
        title: 'Execution status: ${task.executionStatus}',
        actor: 'System',
      ),
    ];

    if (task.submissionJson != null) {
      events.add(
        _AuditEvent(
          time: task.updatedAt,
          type: 'approval',
          title: 'Worker submitted for review',
          actor: 'Worker',
        ),
      );
    }

    return events;
  }

  List<_AuditEvent> _ciEvents(CiRun run) {
    final actor = run.triggeredBy ?? 'System';
    final events = <_AuditEvent>[
      _AuditEvent(
        time: run.createdAt,
        type: 'build',
        title: 'Build created: ${run.name}',
        actor: actor,
      ),
    ];

    if (run.startedAt != null) {
      events.add(
        _AuditEvent(
          time: run.startedAt!,
          type: 'build',
          title: 'Build started: ${run.name}',
          actor: actor,
        ),
      );
    }

    if (run.completedAt != null) {
      events.add(
        _AuditEvent(
          time: run.completedAt!,
          type: 'build',
          title: 'Build ${run.status}: ${run.name}',
          actor: actor,
        ),
      );
    }

    return events;
  }

  /// Reads recent commits via the git engine. Degrades to zero events when
  /// there is no repo or the log throws.
  Future<List<_AuditEvent>> _loadGitEvents(WidgetRef ref) async {
    try {
      final NxtprjGitEngine engine = await ref.read(
        gitEngineProvider(projectId).future,
      );
      final commits = await engine.log(limit: 20);
      return commits.map((c) {
        final shortOid = c.oid.length > 7 ? c.oid.substring(0, 7) : c.oid;
        return _AuditEvent(
          time: c.when,
          type: 'git',
          title: 'Commit $shortOid — ${c.message.trim()}',
          actor: c.author,
        );
      }).toList();
    } catch (_) {
      return const <_AuditEvent>[];
    }
  }
}

/// A single composed audit event derived from real, live data.
class _AuditEvent {
  final DateTime time;
  final String type; // delegation, policy, git, build, approval, human
  final String title;
  final String actor;

  const _AuditEvent({
    required this.time,
    required this.type,
    required this.title,
    required this.actor,
  });
}

class _AuditEventTile extends StatelessWidget {
  final _AuditEvent event;

  const _AuditEventTile({required this.event});

  String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${l.year}-${two(l.month)}-${two(l.day)}';
    final time = '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
    return '$date $time';
  }

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    ChipIntent intent;
    IconData icon;

    switch (event.type) {
      case 'delegation':
        intent = ChipIntent.accent;
        icon = Icons.account_tree;
        break;
      case 'policy':
        intent = ChipIntent.warning;
        icon = Icons.gavel;
        break;
      case 'git':
        intent = ChipIntent.info;
        icon = Icons.commit;
        break;
      case 'build':
        intent = ChipIntent.success;
        icon = Icons.build;
        break;
      case 'approval':
        intent = ChipIntent.warning;
        icon = Icons.lock_clock;
        break;
      case 'human':
        intent = ChipIntent.success;
        icon = Icons.person;
        break;
      default:
        intent = ChipIntent.neutral;
        icon = Icons.info;
    }

    final color = switch (intent) {
      ChipIntent.info => nx.info,
      ChipIntent.success => nx.success,
      ChipIntent.warning => nx.warning,
      ChipIntent.danger => nx.danger,
      ChipIntent.accent => Theme.of(context).colorScheme.primary,
      ChipIntent.neutral => nx.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: NexusCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusChip(event.type, intent: intent, dense: true),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _formatTime(event.time),
                        style: TextStyle(fontSize: 11, color: nx.textFaint),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(event.title, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    event.actor,
                    style: TextStyle(
                      fontSize: 11,
                      color: nx.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
