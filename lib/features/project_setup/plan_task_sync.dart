// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import '../../infrastructure/database/nexus_database.dart';
import '../project_plans/plan_store.dart';
import '../projects/agent_assignment.dart';

/// Walks every plan document under `/PLANS` and turns each unchecked outline
/// item (`- [ ] …`) into a real task, then writes the task id back into the plan
/// line as an HTML-comment marker (`<!-- task:NN -->`). The marker is the
/// dedup key: a re-run skips any line already carrying one, so the same plan
/// item can never spawn a second task.
///
/// Items under a plan file are grouped as subtasks of one parent task per plan
/// (the parent id is parked on the `## Outline` heading), so the task board
/// mirrors the plan structure. Plans without an Outline heading get top-level
/// tasks instead — still fully deduped per line.
///
/// Deterministic — no AI. Runs on setup completion and on demand from the
/// coordinator's `sync_plans_to_tasks` tool.
class PlanTaskSync {
  PlanTaskSync({
    required this.db,
    required this.planStore,
    required this.projectId,
    this.chatSessionPk,
  });

  final NexusDatabase db;
  final PlanStore planStore;
  final int projectId;
  final int? chatSessionPk;

  static final RegExp _marker = RegExp(r'<!--\s*task:(\d+)\s*-->');
  static final RegExp _uncheckedItem = RegExp(r'^(\s*)-\s+\[ \]\s+(.+?)\s*$');

  /// Returns a human-readable summary of what was created.
  Future<PlanSyncResult> sync() async {
    final assignee = await resolveDefaultWorkerPersonaId(db, projectId);
    final nodes = await planStore.list();

    var created = 0;
    var skipped = 0;
    var plansTouched = 0;
    final noAgent = assignee == null;

    for (final node in nodes) {
      if (node.isFolder) continue;
      final result = await _syncFile(node, assignee);
      created += result.created;
      skipped += result.skipped;
      if (result.created > 0) plansTouched++;
    }

    return PlanSyncResult(
      created: created,
      skipped: skipped,
      plansTouched: plansTouched,
      noAgent: noAgent,
    );
  }

  Future<_FileResult> _syncFile(PlanNode node, int? assignee) async {
    final String content;
    try {
      content = await planStore.read(node.path);
    } catch (_) {
      return const _FileResult(0, 0);
    }

    final lines = content.split('\n');
    final planName = _stripExt(node.name);

    // Locate the Outline heading so a per-plan parent task id can be parked on
    // it (enables grouping + dedup of the parent across runs).
    int? outlineIdx;
    int? parentId;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('## Outline')) {
        outlineIdx = i;
        final m = _marker.firstMatch(lines[i]);
        if (m != null) parentId = int.tryParse(m.group(1)!);
        break;
      }
    }

    var created = 0;
    var skipped = 0;
    var changed = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = _uncheckedItem.firstMatch(line);
      if (match == null) continue;
      if (_marker.hasMatch(line)) {
        skipped++;
        continue;
      }
      final itemText = match.group(2)!.trim();
      if (itemText.isEmpty) continue;

      // Lazily create the per-plan parent the first time we need it, and park
      // its id on the Outline heading so future runs reuse it.
      if (parentId == null && outlineIdx != null) {
        parentId = await db.createTaskInProject(
          projectPk: projectId,
          title: planName,
          description: 'Plan: ${node.path}',
          planPath: node.path,
          chatSessionPk: chatSessionPk,
          agentPk: assignee,
        );
        lines[outlineIdx] = '${lines[outlineIdx]} <!-- task:$parentId -->';
        changed = true;
      }

      final taskId = await db.createTaskInProject(
        projectPk: projectId,
        title: itemText,
        description: 'From plan "$planName" → $itemText',
        parentPk: parentId,
        planPath: node.path,
        chatSessionPk: chatSessionPk,
        agentPk: assignee,
      );
      lines[i] = '$line <!-- task:$taskId -->';
      created++;
      changed = true;
    }

    if (changed) {
      await planStore.write(node.path, lines.join('\n'));
    }
    return _FileResult(created, skipped);
  }

  static String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

class _FileResult {
  const _FileResult(this.created, this.skipped);
  final int created;
  final int skipped;
}

/// Outcome of a [PlanTaskSync.sync] run.
class PlanSyncResult {
  const PlanSyncResult({
    required this.created,
    required this.skipped,
    required this.plansTouched,
    required this.noAgent,
  });

  final int created;
  final int skipped;
  final int plansTouched;

  /// True when the project has no agent personas, so created tasks could not be
  /// assigned to anyone.
  final bool noAgent;

  String describe() {
    if (created == 0) {
      return skipped == 0
          ? 'No plan items found to turn into tasks yet.'
          : 'All $skipped plan item(s) already have tasks — nothing new to create.';
    }
    final base =
        'Created $created task(s) across $plansTouched plan(s)'
        '${skipped > 0 ? ' ($skipped already had tasks)' : ''}.';
    return noAgent
        ? '$base No agent persona exists yet, so they are unassigned — '
              'create a worker agent in the Agents hub.'
        : base;
  }
}
