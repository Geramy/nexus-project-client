// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// A compact, LIVE agent-activity readout for the top bar: which agent is
/// running, the task it's on, and its state (working / complete / stopped).
/// Driven straight off the project's task stream, so it updates as the
/// orchestrator picks up, advances, and finishes work — no polling.
///
/// An agent here is a CONCURRENT WORKER (one running task = one agent slot), so
/// four workers of the same persona show as four — not one. A small square count
/// box (themed with the normal colour scheme) sits to the LEFT of the coloured
/// state chip and shows how many agents are working.
///
/// The chip shows ONE representative: the focused worker (if the user pinned
/// one), else the first working worker, else the first agent (in persona order)
/// that has any task. When MORE THAN TWO agents are working at once, clicking it
/// drops down the full list so the user can FOCUS one; otherwise it just opens
/// the Tasks view.
library;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';

/// The worker (by task pk) the user has pinned in the top-bar feed, per project
/// (null = auto: first working). Auto-falls back if that worker leaves the feed.
final focusedWorkerProvider = StateProvider.family<int?, int>((ref, _) => null);

enum _AgentState { working, complete, stopped }

class _AgentActivity {
  const _AgentActivity(this.taskPk, this.agent, this.task, this.state);
  final int taskPk;
  final String agent;
  final String task;
  final _AgentState state;
}

class AgentFeedIndicator extends ConsumerWidget {
  const AgentFeedIndicator({super.key, this.narrow = false});

  /// On phones, render icon + count only (the tooltip/menu still has detail).
  final bool narrow;

  /// Execution states where an agent is ACTIVELY running a turn right now — must
  /// match `_ActiveAgentsChip` next to the orchestration controls so the two
  /// counts agree. NOTE: this excludes the PARKED between-stage states
  /// (queued / submitted / verified / built) and idle/Todo work — those have no
  /// running agent, so counting them inflated the feed (and pulled in setup/
  /// coordinator tasks that were merely sitting around).
  static const _activeExec = {
    TaskExecStatus.running,
    TaskExecStatus.verifying,
    TaskExecStatus.building,
    TaskExecStatus.merging,
  };

  static const int _autoFocus = -1;
  static const int _openTasks = -2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projectId = ref.watch(currentProjectIdProvider);
    final clientId = ref.watch(currentClientIdProvider);
    final tasks =
        ref.watch(allTasksForProjectProvider(projectId)).value ??
        const [];
    final personas =
        ref.watch(agentPersonasForClientProvider(clientId)).value ??
        const [];
    final nameOf = {for (final p in personas) p.agent_pk: p.name};
    String agentName(int? pk) => (pk == null ? null : nameOf[pk]) ?? 'Agent';

    // Each currently-processing task is one concurrent worker (one connection).
    final workers =
        tasks
            .where(
              (t) =>
                  t.task_agent_fk != null &&
                  _activeExec.contains(t.executionStatus),
            )
            .toList()
          ..sort((a, b) => a.task_pk.compareTo(b.task_pk));
    final workingCount = workers.length;

    // Feed entries = the active workers; if none, a single representative (the
    // first agent-assigned task) so the chip still shows the latest agent.
    final List<_AgentActivity> entries;
    if (workers.isNotEmpty) {
      entries = [
        for (final t in workers)
          _AgentActivity(
            t.task_pk,
            agentName(t.task_agent_fk),
            t.title,
            _AgentState.working,
          ),
      ];
    } else {
      final assigned =
          tasks.where((t) => t.task_agent_fk != null).toList()
            ..sort((a, b) => a.task_pk.compareTo(b.task_pk));
      final first = assigned.firstOrNull;
      entries = first == null
          ? const []
          : [
              _AgentActivity(
                first.task_pk,
                agentName(first.task_agent_fk),
                first.title,
                first.status == TaskStatus.done
                    ? _AgentState.complete
                    : _AgentState.stopped,
              ),
            ];
    }

    final focused = ref.watch(focusedWorkerProvider(projectId));
    final rep =
        (focused == null
            ? null
            : entries.firstWhereOrNull((e) => e.taskPk == focused)) ??
        entries.firstWhereOrNull((e) => e.state == _AgentState.working) ??
        entries.firstOrNull;

    final tooltip = entries.isEmpty
        ? 'No agents have tasks yet'
        : entries
              .map(
                (e) => '#${e.taskPk} ${e.agent}: ${e.task} — ${_label(e.state)}',
              )
              .join('\n');

    final chip = _buildChip(theme, rep, workingCount);

    // Dropdown to focus an agent only matters with MORE THAN TWO working at once;
    // otherwise keep the simple tap-through to the Tasks view.
    if (workingCount > 2) {
      return PopupMenuButton<int>(
        tooltip: '',
        position: PopupMenuPosition.under,
        onSelected: (v) {
          final notifier = ref.read(focusedWorkerProvider(projectId).notifier);
          if (v == _openTasks) {
            ref.read(currentMainViewProvider.notifier).setView(MainView.tasks);
          } else if (v == _autoFocus) {
            notifier.state = null;
          } else {
            notifier.state = v;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _autoFocus,
            child: Row(
              children: [
                Icon(
                  focused == null ? Icons.check : Icons.auto_awesome,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                const Text('Auto (first working)'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          for (final e in entries)
            PopupMenuItem(value: e.taskPk, child: _menuRow(theme, e, focused)),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _openTasks,
            child: Row(
              children: [
                Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                const Text('Open Tasks view'),
              ],
            ),
          ),
        ],
        child: Tooltip(message: tooltip, child: chip),
      );
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () =>
            ref.read(currentMainViewProvider.notifier).setView(MainView.tasks),
        child: chip,
      ),
    );
  }

  /// A small square count box (normal colour scheme) on the LEFT, then the
  /// state-coloured agent chip.
  Widget _buildChip(ThemeData theme, _AgentActivity? rep, int workingCount) {
    final ({Color bg, Color fg})? pal = rep == null
        ? null
        : _palette(rep.state, theme.brightness == Brightness.dark);
    final fg = pal?.fg ?? theme.colorScheme.onSurfaceVariant;

    final chip = Container(
      constraints: BoxConstraints(maxWidth: narrow ? 44 : 240),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: pal?.bg,
        borderRadius: BorderRadius.circular(6),
        border: pal == null ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_outlined, size: 14, color: fg),
          if (!narrow) ...[
            const SizedBox(width: 6),
            Flexible(
              child: rep == null
                  ? Text(
                      'No active agents',
                      style: TextStyle(fontSize: 12, color: fg),
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: rep.agent,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          TextSpan(
                            text: ' · ${rep.task}',
                            style: TextStyle(fontSize: 12, color: fg),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ],
      ),
    );

    if (workingCount < 1) return chip;

    // Themed (normal colour-scheme) square counter to the LEFT of the chip.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            '$workingCount',
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 6),
        chip,
      ],
    );
  }

  Widget _menuRow(ThemeData theme, _AgentActivity e, int? focused) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: _dotColor(e.state),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.agent,
                style: TextStyle(
                  fontWeight: e.taskPk == focused
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                // Prefix the task number — auto-generated titles look alike, so
                // "#314" makes each row easy to tell apart at a glance.
                '#${e.taskPk} · ${e.task} — ${_label(e.state)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (e.taskPk == focused) ...[
          const SizedBox(width: 8),
          Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
        ],
      ],
    );
  }

  static String _label(_AgentState s) => switch (s) {
    _AgentState.working => 'working',
    _AgentState.complete => 'complete',
    _AgentState.stopped => 'stopped',
  };

  /// Saturated dot colour for the dropdown rows (legible on any menu surface).
  static Color _dotColor(_AgentState s) => switch (s) {
    _AgentState.working => const Color(0xFFEF6C00),
    _AgentState.complete => const Color(0xFF2E7D32),
    _AgentState.stopped => const Color(0xFFC62828),
  };

  /// State → (background, foreground), per theme brightness.
  ///
  /// Dark themes (Nebula/"Galactia" + Midnight) — solid chips, WHITE text:
  ///   • complete → bg #1B5E20 (dark green)   · fg #FFFFFF
  ///   • working  → bg #E65100 (orange)       · fg #FFFFFF
  ///   • stopped  → bg #C62828 (red)          · fg #FFFFFF
  /// Light theme (Daylight) — soft chips, BLACK text:
  ///   • complete → bg #C8E6C9 (light green)  · fg #000000
  ///   • working  → bg #FFE0B2 (light orange) · fg #000000
  ///   • stopped  → bg #FFCDD2 (light red)    · fg #000000
  static ({Color bg, Color fg}) _palette(_AgentState s, bool dark) {
    const white = Color(0xFFFFFFFF);
    const black = Color(0xFF000000);
    switch (s) {
      case _AgentState.complete:
        return dark
            ? (bg: const Color(0xFF1B5E20), fg: white)
            : (bg: const Color(0xFFC8E6C9), fg: black);
      case _AgentState.working:
        return dark
            ? (bg: const Color(0xFFE65100), fg: white)
            : (bg: const Color(0xFFFFE0B2), fg: black);
      case _AgentState.stopped:
        return dark
            ? (bg: const Color(0xFFC62828), fg: white)
            : (bg: const Color(0xFFFFCDD2), fg: black);
    }
  }
}
