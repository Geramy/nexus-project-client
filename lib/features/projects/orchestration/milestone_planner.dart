// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Pure, deterministic milestone batching for the Templater stage.
///
/// The Templater splits a project's backlog into sequential milestone batches so
/// agents code one shallow batch at a time, gating CI between them instead of
/// letting errors pile up across the whole project. Batching is epic-aware: a
/// story epic already designates a topic group, so its tasks are kept adjacent
/// and the backlog is then cut into roughly-equal contiguous chunks. Pulled out
/// of the orchestrator so it's trivially unit-testable.
library;

/// One unit of work to be placed into a milestone batch.
class MilestoneItem {
  /// The task's primary key.
  final int id;

  /// The epic (story) this task rolls up to, or null when it's "loose" (under no
  /// epic). Epic-mates share a key so they land adjacent — and usually together
  /// — in the same batch.
  final int? groupKey;

  /// Stable ordering signal (e.g. createdAt millis, or task_pk as a fallback).
  final int order;

  const MilestoneItem({
    required this.id,
    required this.groupKey,
    required this.order,
  });
}

/// How many milestone batches a backlog of [taskCount] tasks gets: `ceil(n / 5)`,
/// minimum 1. So ≤5 → 1 (base → all tasks → final CI, no intermediate
/// milestones), 6–10 → 2 (one milestone ~halfway), 11–15 → 3, and so on.
int milestoneBatchCount(int taskCount) {
  if (taskCount <= 0) return 0;
  return (taskCount + 4) ~/ 5; // ceil(n / 5)
}

/// Assign every item a 0-based milestone batch index.
///
/// Epic-mates are kept contiguous (ordered by their epic's first appearance) so
/// batch boundaries prefer to fall on topic edges; the ordered backlog is then
/// split into [milestoneBatchCount] nearly-equal contiguous chunks (earlier
/// batches take the remainder) so each milestone stays shallow. A large epic that
/// exceeds a chunk is allowed to span the boundary rather than blow up one batch.
Map<int, int> assignMilestones(List<MilestoneItem> items) {
  final out = <int, int>{};
  final n = items.length;
  if (n == 0) return out;

  final count = milestoneBatchCount(n);
  if (count <= 1) {
    for (final it in items) {
      out[it.id] = 0;
    }
    return out;
  }

  // Anchor each item to its epic's first-seen order so epic-mates cluster; loose
  // items flow by their own order.
  final groupFirst = <int, int>{};
  for (final it in items) {
    final g = it.groupKey;
    if (g != null) {
      final prev = groupFirst[g];
      if (prev == null || it.order < prev) groupFirst[g] = it.order;
    }
  }

  final ordered = [...items]..sort((a, b) {
    final ka = a.groupKey == null ? a.order : groupFirst[a.groupKey]!;
    final kb = b.groupKey == null ? b.order : groupFirst[b.groupKey]!;
    if (ka != kb) return ka.compareTo(kb);
    final ga = a.groupKey ?? -1;
    final gb = b.groupKey ?? -1;
    if (ga != gb) return ga.compareTo(gb);
    return a.order.compareTo(b.order);
  });

  // Nearly-equal contiguous chunks; the first (n % count) batches get one extra.
  final base = n ~/ count;
  final extra = n % count;
  var idx = 0;
  for (var b = 0; b < count; b++) {
    final size = base + (b < extra ? 1 : 0);
    for (var k = 0; k < size; k++) {
      out[ordered[idx++].id] = b;
    }
  }
  return out;
}
