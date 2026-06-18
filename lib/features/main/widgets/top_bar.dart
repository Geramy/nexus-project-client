// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/main/widgets/agent_feed_indicator.dart';
import 'package:nexus_projects_client/features/projects/project_switch.dart';

/// Top bar extracted from main_shell.dart during organization refactor (2026-05).
/// Contains prominent client indicator + project switcher + connection mode.
class TopBar extends ConsumerWidget {
  final String connectionMode;

  const TopBar({required this.connectionMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phones can't fit the full bar (wordmark + client + project + connection
    // label), so drop the wordmark and shrink to an icon-only toggle there.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, size: 22),
              if (!narrow) ...[
                const SizedBox(width: 8),
                const Text(
                  'Nexus Projects',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ],
          ),
          SizedBox(width: narrow ? 10 : 24),

          // Client switcher — the multi-tenancy root, given the same dropdown
          // treatment as the project switcher next to it so they're managed the
          // same way.
          Consumer(
            builder: (context, ref, _) {
              final currentClientId = ref.watch(currentClientIdProvider);
              final clients = ref.watch(allClientsProvider).value ?? const [];
              final clientName =
                  clients
                      .where((c) => c.client_pk == currentClientId)
                      .firstOrNull
                      ?.name ??
                  currentClientId.toString();

              return PopupMenuButton<int>(
                tooltip: 'Switch client',
                position: PopupMenuPosition.under,
                onSelected: (id) => _switchClient(context, ref, id),
                itemBuilder: (_) => [
                  for (final c in clients)
                    PopupMenuItem(
                      value: c.client_pk,
                      child: Row(
                        children: [
                          Icon(
                            c.client_pk == currentClientId
                                ? Icons.check
                                : Icons.business,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  constraints: BoxConstraints(maxWidth: narrow ? 120 : 170),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business, size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          clientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Project switcher — a dropdown so exactly ONE project is focused at a
          // time. Switching away from a project whose agents are running asks for
          // confirmation and pauses them, so an accidental click can't hand all
          // your concurrency to an unfinished project.
          Flexible(
            child: Consumer(
              builder: (context, ref, _) {
                final currentClientId = ref.watch(currentClientIdProvider);
                final currentProjectId = ref.watch(currentProjectIdProvider);
                final projects =
                    ref
                        .watch(projectsForClientProvider(currentClientId))
                        .value ??
                    const [];
                final projectName =
                    projects
                        .where((p) => p.project_pk == currentProjectId)
                        .firstOrNull
                        ?.name ??
                    currentProjectId.toString();

                return PopupMenuButton<int>(
                  tooltip: 'Switch project',
                  position: PopupMenuPosition.under,
                  onSelected: (id) => swapToProject(context, ref, id),
                  itemBuilder: (_) => [
                    for (final p in projects)
                      PopupMenuItem(
                        value: p.project_pk,
                        child: Row(
                          children: [
                            Icon(
                              p.project_pk == currentProjectId
                                  ? Icons.check
                                  : Icons.folder_open,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_open, size: 14),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            projectName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const Spacer(),

          // Live agent feed: which agent is running, the task it's on, and its
          // state (working / complete / stopped) — sits between the project
          // breadcrumb and the connection toggle.
          AgentFeedIndicator(narrow: narrow),
          SizedBox(width: narrow ? 8 : 12),

          // Connection mode toggle (icon-only on phones to save width).
          Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(connectionModeProvider);
              final icon = Icon(
                mode == 'local' ? Icons.computer : Icons.cloud,
                size: 16,
              );
              void toggle() =>
                  ref.read(connectionModeProvider.notifier).toggle();
              if (narrow) {
                return IconButton(
                  tooltip: mode == 'local' ? 'Local' : 'Remote',
                  onPressed: toggle,
                  icon: icon,
                );
              }
              return OutlinedButton.icon(
                onPressed: toggle,
                icon: icon,
                label: Text(mode == 'local' ? 'Local' : 'Remote'),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Switch the focused CLIENT (and jump to its first project). Like the project
  /// switcher, it confirms leaving a running project and stops it first —
  /// selectProject then pauses the old project + frees its connections.
  Future<void> _switchClient(
    BuildContext context,
    WidgetRef ref,
    int clientId,
  ) async {
    if (clientId == ref.read(currentClientIdProvider)) return;
    if (!await confirmLeaveProject(context, ref)) return;
    ref.read(currentClientIdProvider.notifier).selectClient(clientId);
    final db = ref.read(nexusDatabaseProvider);
    final projs = await db.getProjectsForClient(clientId);
    if (projs.isNotEmpty) {
      ref
          .read(currentProjectIdProvider.notifier)
          .selectProject(projs.first.project_pk);
    }
  }
}
