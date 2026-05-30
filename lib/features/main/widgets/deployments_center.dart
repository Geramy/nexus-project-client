// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/builds/ci_run_tree.dart' show StatusChip;

/// Deployments center: a client-scoped, live feed of deployments and preview
/// environments with status, target environment and timing.
class DeploymentsCenter extends ConsumerWidget {
  const DeploymentsCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentClientId = ref.watch(currentClientIdProvider);
    final deploysAsync = ref.watch(deploymentsForClientProvider(currentClientId));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: deploysAsync.when(
              data: (deploys) {
                if (deploys.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rocket_launch, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('No deployments yet.', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: deploys.length,
                  itemBuilder: (c, i) {
                    final d = deploys[i];
                    final parts = <String>[
                      d.environment,
                      if (d.triggeredBy != null && d.triggeredBy!.isNotEmpty) 'by ${d.triggeredBy}',
                      _relativeTime(d.createdAt),
                    ];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.rocket_launch_outlined),
                        title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(parts.join(' • '),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        trailing: StatusChip(status: d.status),
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

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
