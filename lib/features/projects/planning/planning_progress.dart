// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/legacy.dart';

/// Live progress of a [ProjectPlanningRun], surfaced project-wide so the Tasks
/// view (and anywhere else) can show what the planning agent is doing after the
/// user has been redirected away from the setup chat.
class PlanningProgress {
  const PlanningProgress({this.running = false, this.lines = const []});

  /// True while a planning run is in flight.
  final bool running;

  /// Accumulated progress lines, oldest first.
  final List<String> lines;

  /// The most recent line (what to show in a one-line banner), or null.
  String? get latest => lines.isEmpty ? null : lines.last;

  PlanningProgress copyWith({bool? running, List<String>? lines}) =>
      PlanningProgress(
        running: running ?? this.running,
        lines: lines ?? this.lines,
      );
}

/// Drives [PlanningProgress] for one project. Callers of `ProjectPlanningRun`
/// wire its `onProgress` into [add] (between [start] and [finish]).
class PlanningProgressNotifier extends StateNotifier<PlanningProgress> {
  PlanningProgressNotifier() : super(const PlanningProgress());

  /// Begin a fresh run (clears prior lines).
  void start() => state = const PlanningProgress(running: true, lines: []);

  /// Append a progress line.
  void add(String line) =>
      state = state.copyWith(running: true, lines: [...state.lines, line]);

  /// Mark the run finished (keeps the last lines so the banner can briefly show
  /// the closing "✓ built N tasks" before the caller clears it).
  void finish() => state = state.copyWith(running: false);
}

/// Project-scoped planning progress. Not auto-disposed so a background run that
/// outlives the originating screen keeps reporting.
final planningProgressProvider =
    StateNotifierProvider.family<
      PlanningProgressNotifier,
      PlanningProgress,
      int
    >((ref, projectId) => PlanningProgressNotifier());
