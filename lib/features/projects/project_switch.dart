// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Shared helpers for LEAVING the currently-focused project (switching to
/// another, or creating a new one). The orchestrator is auto-disposed per
/// project, so leaving stops the old project's agents from spawning; we ALSO
/// free the inference connections immediately so the next project gets the full
/// connection budget right away (an in-flight agent turn would otherwise keep its
/// socket open). Used by both the top-bar switcher and the left sidebar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_shell_provider.dart';
import '../../core/providers/database_provider.dart';
import '../../infrastructure/inference/inference_backend_factory.dart'
    show resetInferenceConnections;

/// Confirm leaving the focused project when its orchestration is RUNNING (its
/// agents will stop and free their connections; they resume when refocused).
/// Returns true if the caller should proceed, false if the user cancelled.
Future<bool> confirmLeaveProject(BuildContext context, WidgetRef ref) async {
  final currentId = ref.read(currentProjectIdProvider);
  final db = ref.read(nexusDatabaseProvider);
  final proj = await db.getProjectById(currentId);
  if (proj?.orchestrationState != 'running') return true; // nothing running
  if (!context.mounted) return false;
  final name = proj?.name ?? 'this project';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Swap projects?'),
      content: Text(
        'The agents currently working on "$name" will stop and free their '
        'connections so the next project gets them right away. Press Start on '
        '"$name" later to resume it.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Stop & swap'),
        ),
      ],
    ),
  );
  if (ok == true) {
    // STOP the old project immediately (set non-running so its orchestrator
    // stops pumping) and free its connections — covers the New-Project flow,
    // where the old project stays focused through the whole setup dialog and
    // would otherwise keep re-opening sockets and 429 the new one.
    await db.setProjectOrchestrationState(currentId, 'paused');
    resetInferenceConnections();
  }
  return ok == true;
}

/// Switch focus to [newId]: confirm leaving the current project, switch (which
/// auto-disposes the old orchestrator so it stops spawning), then immediately
/// free the inference connections for the new project.
Future<void> swapToProject(
  BuildContext context,
  WidgetRef ref,
  int newId,
) async {
  if (newId == ref.read(currentProjectIdProvider)) return;
  if (!await confirmLeaveProject(context, ref)) return;
  ref.read(currentProjectIdProvider.notifier).selectProject(newId);
  resetInferenceConnections();
}
