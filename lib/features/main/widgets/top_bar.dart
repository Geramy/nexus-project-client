// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';

/// Top bar extracted from main_shell.dart during organization refactor (2026-05).
/// Contains prominent client indicator + project switcher + connection mode.
class TopBar extends ConsumerWidget {
  final String connectionMode;

  const TopBar({required this.connectionMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Row(
            children: [
              Icon(Icons.hub_outlined, size: 22),
              SizedBox(width: 8),
              Text('Nexus Projects', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ],
          ),
          const SizedBox(width: 24),

          // Prominent Current Client indicator (multi-tenancy root)
          Consumer(
            builder: (context, ref, _) {
              final currentClientId = ref.watch(currentClientIdProvider);
              final clientsAsync = ref.watch(allClientsProvider);

              final clientName = clientsAsync.when(
                data: (clients) {
                  final match = clients.where((c) => c.client_pk == currentClientId).firstOrNull;
                  return match?.name ?? currentClientId.toString();
                },
                loading: () => currentClientId.toString(),
                error: (_, __) => currentClientId.toString(),
              );

              return Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.business, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        clientName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Project Switcher (simplified for now)
          Flexible(
            child: Consumer(
              builder: (context, ref, _) {
                final currentClientId = ref.watch(currentClientIdProvider);
                final currentProjectId = ref.watch(currentProjectIdProvider);
                final projectsAsync = ref.watch(projectsForClientProvider(currentClientId));

                final projectName = projectsAsync.when(
                  data: (projects) {
                    final match = projects.where((p) => p.project_pk == currentProjectId).firstOrNull;
                    return match?.name ?? currentProjectId.toString();
                  },
                  loading: () => currentProjectId.toString(),
                  error: (_, __) => currentProjectId.toString(),
                );

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    ],
                  ),
                );
              },
            ),
          ),

          const Spacer(),

          // Connection mode toggle (from prior work)
          Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(connectionModeNotifierProvider);
              return OutlinedButton.icon(
                onPressed: () => ref.read(connectionModeNotifierProvider.notifier).toggle(),
                icon: Icon(mode == 'local' ? Icons.computer : Icons.cloud, size: 16),
                label: Text(mode == 'local' ? 'Local' : 'Remote'),
              );
            },
          ),
        ],
      ),
    );
  }
}
