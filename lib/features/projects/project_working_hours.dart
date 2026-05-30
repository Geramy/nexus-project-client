// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart' show Project;

/// Pure helpers for a project's working-hours window. The window is stored on
/// the project as minutes-from-midnight ([Project.workHoursStart]/[workHoursEnd])
/// plus a Mon..Sun weekday bitmask ([Project.workDaysMask], bit 0 = Monday).
/// When [Project.workHoursEnabled] is false the project has no time gate and
/// the loop may run any time.

/// True if [now] (defaults to local now) falls inside the project's working
/// hours. Always true when the gate is disabled or the window is unset.
bool isWithinWorkingHours(Project project, {DateTime? now}) {
  if (!project.workHoursEnabled) return true;
  final start = project.workHoursStart;
  final end = project.workHoursEnd;
  if (start == null || end == null || start == end) return true;

  final t = now ?? DateTime.now();

  // Weekday gate: DateTime.weekday is 1 (Mon) .. 7 (Sun) → bit 0 .. 6.
  final mask = project.workDaysMask ?? 0;
  if (mask != 0) {
    final bit = 1 << (t.weekday - 1);
    if (mask & bit == 0) return false;
  }

  final minutes = t.hour * 60 + t.minute;
  if (start < end) {
    return minutes >= start && minutes < end;
  }
  // Window wraps past midnight (e.g. 22:00 → 06:00).
  return minutes >= start || minutes < end;
}

/// Format minutes-from-midnight as "HH:mm" (24h). Returns "--:--" for null.
String formatMinutesOfDay(int? minutes) {
  if (minutes == null) return '--:--';
  final m = minutes % (24 * 60);
  final h = m ~/ 60;
  final mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

/// Short Mon..Sun labels indexed by bit (0 = Monday).
const List<String> kWeekdayShortLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Human summary of the working-hours config for display.
String workingHoursSummary(Project project) {
  if (!project.workHoursEnabled) return 'Always (no time limit)';
  final start = project.workHoursStart;
  final end = project.workHoursEnd;
  if (start == null || end == null) return 'Always (no time limit)';
  final window = '${formatMinutesOfDay(start)}–${formatMinutesOfDay(end)}';
  final mask = project.workDaysMask ?? 0;
  if (mask == 0) return '$window, every day';
  final days = <String>[];
  for (var i = 0; i < 7; i++) {
    if (mask & (1 << i) != 0) days.add(kWeekdayShortLabels[i]);
  }
  return '$window, ${days.join(', ')}';
}
