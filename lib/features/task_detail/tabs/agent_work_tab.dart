// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show AgentPersona, ChatMessage, Task;

import '../../../shared/ui/nexus_ui.dart';

/// Agent Work tab — a live, real-time feed of the worker agent's execution on
/// this task. The feed is assembled from the worker chat-session messages
/// (`worker_session_fk` on the Task), streamed live via Drift's `.watch()`.
class AgentWorkTab extends ConsumerWidget {
  final int taskId;
  const AgentWorkTab({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider);
    final tasksAsync = ref.watch(allTasksForProjectProvider(projectId));

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading task: $e')),
      data: (all) {
        Task? task;
        for (final t in all) {
          if (t.task_pk == taskId) {
            task = t;
            break;
          }
        }
        if (task == null) {
          return const Center(child: Text('Task not found.'));
        }
        return _buildBody(context, ref, task);
      },
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Task task) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AgentHeaderCard(task: task),
          if (task.submissionJson != null) ...[Gap.md, _SubmittedBanner()],
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Activity Feed', dense: true),
          Gap.sm,
          _ActivityFeed(workerSessionFk: task.worker_session_fk),
        ],
      ),
    );
  }
}

/// Header: assigned agent name + title and a status chip for `executionStatus`.
class _AgentHeaderCard extends ConsumerWidget {
  final Task task;
  const _AgentHeaderCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    final agentFk = task.task_agent_fk;

    return NexusCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.smart_toy, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FutureBuilder<AgentPersona?>(
              future: agentFk == null
                  ? Future<AgentPersona?>.value(null)
                  : db.resolveAgentPersona(agentFk),
              builder: (context, snapshot) {
                final agent = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent != null
                          ? 'Assigned agent: ${agent.name}'
                          : 'No agent assigned to this task.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (agent?.title != null && agent!.title!.isNotEmpty)
                      Text(
                        agent.title!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.nx.textMuted,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatusChip(status: task.executionStatus),
        ],
      ),
    );
  }
}

/// Status chip reflecting the task's execution phase.
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  ChipIntent _intentFor() {
    switch (status) {
      case 'running':
      case 'verifying':
        return ChipIntent.info;
      case 'queued':
      case 'submitted':
        return ChipIntent.warning;
      case 'passed':
        return ChipIntent.success;
      case 'failed':
        return ChipIntent.danger;
      case 'idle':
      default:
        return ChipIntent.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StatusChip(status, intent: _intentFor(), dense: true);
  }
}

/// Small banner shown when the worker has submitted work for review.
class _SubmittedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final warning = context.nx.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.nx.tintOf(warning),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: warning),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'Submitted for review.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live activity feed = worker chat-session messages, streamed live.
class _ActivityFeed extends ConsumerWidget {
  final int? workerSessionFk;
  const _ActivityFeed({required this.workerSessionFk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionFk = workerSessionFk;
    if (sessionFk == null) {
      return const EmptyState(
        icon: Icons.hourglass_empty,
        title: 'No worker yet',
        message: 'This task has not been picked up by a worker agent yet.',
        compact: true,
      );
    }

    final db = ref.watch(nexusDatabaseProvider);
    return StreamBuilder<List<ChatMessage>>(
      stream: db.watchChatMessagesForSession(sessionFk),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading feed: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final messages = snapshot.data ?? const <ChatMessage>[];
        if (messages.isEmpty) {
          return const EmptyState(
            icon: Icons.timeline,
            title: 'No activity yet',
            message: 'Worker session started — no messages yet.',
            compact: true,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final m in messages) _FeedRow(message: m)],
        );
      },
    );
  }
}

/// A single feed row rendering one worker chat message.
class _FeedRow extends StatelessWidget {
  final ChatMessage message;
  const _FeedRow({required this.message});

  ({IconData icon, ChipIntent intent, String label}) _roleStyle() {
    switch (message.role) {
      case 'assistant':
        return (
          icon: Icons.smart_toy,
          intent: ChipIntent.info,
          label: 'assistant',
        );
      case 'system':
        return (
          icon: Icons.settings,
          intent: ChipIntent.neutral,
          label: 'system',
        );
      case 'tool':
        return (icon: Icons.build, intent: ChipIntent.accent, label: 'tool');
      case 'user':
        return (icon: Icons.person, intent: ChipIntent.success, label: 'user');
      default:
        return (
          icon: Icons.chat_bubble_outline,
          intent: ChipIntent.neutral,
          label: message.role,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _roleStyle();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, size: 16, color: context.nx.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(style.label, intent: style.intent, dense: true),
                const SizedBox(height: 2),
                SelectableText(
                  message.content.isEmpty ? '(no content)' : message.content,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
