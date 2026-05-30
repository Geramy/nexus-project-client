// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart' show Project;
import 'package:nexus_projects_client/features/projects/project_working_hours.dart';

/// Start / Pause / Stop control bar for a project's autonomous worker-spawn
/// loop. Flips the project's `orchestrationState` in the DB; the orchestration
/// driver (a provider keyed by project) watches that state and reacts.
class ProjectOrchestrationControls extends ConsumerWidget {
  final int projectId;

  /// Compact mode renders just the buttons (for a toolbar); otherwise it adds
  /// a status line + the working-hours summary.
  final bool compact;

  const ProjectOrchestrationControls({
    super.key,
    required this.projectId,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    return StreamBuilder<Project?>(
      stream: db.watchProject(projectId),
      builder: (context, snap) {
        final project = snap.data;
        final state = project?.orchestrationState ?? 'stopped';
        final running = state == 'running';
        final paused = state == 'paused';

        Future<void> set(String s) => db.setProjectOrchestrationState(projectId, s);

        final buttons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!running)
              FilledButton.icon(
                onPressed: () => set('running'),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(paused ? 'Resume' : 'Start'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: () => set('paused'),
                icon: const Icon(Icons.pause, size: 18),
                label: const Text('Pause'),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: state == 'stopped' ? null : () => set('stopped'),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop'),
            ),
          ],
        );

        if (compact) return buttons;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StateDot(state: state),
                const SizedBox(width: 8),
                Text(
                  switch (state) {
                    'running' => 'Orchestration running',
                    'paused' => 'Orchestration paused',
                    _ => 'Orchestration stopped',
                  },
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (project != null)
              Text(
                'Working hours: ${workingHoursSummary(project)}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
            const SizedBox(height: 12),
            buttons,
          ],
        );
      },
    );
  }
}

class _StateDot extends StatelessWidget {
  final String state;
  const _StateDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'running' => Colors.green,
      'paused' => Colors.orange,
      _ => Colors.grey,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Editor for a project's working-hours window: an enable toggle, start/end
/// time pickers, and weekday chips. Writes through to the DB on every change.
class ProjectWorkingHoursEditor extends ConsumerWidget {
  final int projectId;
  const ProjectWorkingHoursEditor({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    return StreamBuilder<Project?>(
      stream: db.watchProject(projectId),
      builder: (context, snap) {
        final project = snap.data;
        if (project == null) return const SizedBox.shrink();

        final enabled = project.workHoursEnabled;
        final start = project.workHoursStart;
        final end = project.workHoursEnd;
        final mask = project.workDaysMask ?? 0;

        Future<void> save({bool? en, int? s, int? e, int? dm, bool clearStart = false, bool clearEnd = false}) {
          return db.setProjectWorkingHours(
            projectId,
            enabled: en ?? enabled,
            start: clearStart ? null : (s ?? start),
            end: clearEnd ? null : (e ?? end),
            daysMask: dm ?? mask,
          );
        }

        Future<void> pick(bool isStart) async {
          final initialMin = (isStart ? start : end) ?? (isStart ? 9 * 60 : 17 * 60);
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: initialMin ~/ 60, minute: initialMin % 60),
          );
          if (picked == null) return;
          final m = picked.hour * 60 + picked.minute;
          await save(s: isStart ? m : null, e: isStart ? null : m);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limit work to specific hours'),
              subtitle: const Text('Outside these hours the loop idles even while running.'),
              value: enabled,
              onChanged: (v) => save(en: v),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => pick(true),
                      child: Text('Start: ${formatMinutesOfDay(start)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => pick(false),
                      child: Text('End: ${formatMinutesOfDay(end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Active days', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(kWeekdayShortLabels[i]),
                      selected: mask == 0 || (mask & (1 << i)) != 0,
                      onSelected: (sel) {
                        // mask 0 means "every day"; first toggle materializes it.
                        var m = mask == 0 ? 0x7F : mask;
                        if (sel) {
                          m |= (1 << i);
                        } else {
                          m &= ~(1 << i);
                        }
                        save(dm: m & 0x7F);
                      },
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
