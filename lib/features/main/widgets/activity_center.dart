// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';

/// Activity / Audit feed center: a client-scoped, live feed of every agent and
/// human action, with actor, action and time.
class ActivityCenter extends ConsumerWidget {
  const ActivityCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentClientId = ref.watch(currentClientIdProvider);
    final activitiesAsync = ref.watch(activityLogsForClientProvider(currentClientId));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Project Activity & Audit Feed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Expanded(
            child: activitiesAsync.when(
              data: (logs) {
                if (logs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('No activity yet for this client.',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final meta = <String>[
                      if (log.actorId != null && log.actorId!.isNotEmpty)
                        '${log.actorType}: ${log.actorId}'
                      else
                        log.actorType,
                      _relativeTime(log.createdAt),
                    ];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: Icon(_actionIcon(log.action), size: 20),
                        title: Text(log.action, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (log.summary != null && log.summary!.isNotEmpty) Text(log.summary!),
                            Text(meta.join(' • '),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _actionIcon(String action) {
  if (action.startsWith('task')) return Icons.task_alt;
  if (action.startsWith('build') || action.startsWith('ci')) return Icons.build;
  if (action.startsWith('deploy')) return Icons.rocket_launch;
  if (action.startsWith('git') || action.startsWith('merge')) return Icons.merge_type;
  if (action.startsWith('agent')) return Icons.smart_toy;
  return Icons.history;
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
