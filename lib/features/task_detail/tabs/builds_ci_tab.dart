// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/builds/ci_run_tree.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show CiRun;

import '../../../shared/ui/nexus_ui.dart';

/// Builds & CI tab — live view of CI runs / jobs / steps related to this task,
/// streamed from the local Drift database. Read-only.
class BuildsCiTab extends ConsumerWidget {
  final int projectPk;
  final int taskId;
  const BuildsCiTab({super.key, required this.projectPk, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    return StreamBuilder<List<CiRun>>(
      stream: db.watchCiRunsForProject(projectPk),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final allRuns = snapshot.data ?? const <CiRun>[];
        final runs = allRuns.where((run) => run.task_fk == taskId).toList();
        if (runs.isEmpty) {
          return const CiRunsEmptyState(
            icon: Icons.construction,
            message: 'No builds or CI runs for this task yet.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: runs.length,
          itemBuilder: (context, i) => CiRunCard(db: db, run: runs[i]),
        );
      },
    );
  }
}
