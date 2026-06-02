// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/database/nexus_database.dart' show Project;
import 'project_type.dart';

/// Reactive single project row for [projectId].
final projectByIdProvider =
    StreamProvider.family<Project?, int>((ref, projectId) {
  return ref.watch(nexusDatabaseProvider).watchProject(projectId);
});

/// The [ProjectType] of a given project (resolved from its `projectType`
/// column, defaulting to application-development for legacy/blank rows).
final projectTypeProvider = Provider.family<ProjectType, int>((ref, projectId) {
  final row = ref.watch(projectByIdProvider(projectId)).valueOrNull;
  return projectTypeByKey(row?.projectType);
});

/// The [ProjectType] of the currently-selected project — what the shell gates on.
final currentProjectTypeProvider = Provider<ProjectType>((ref) {
  final projectId = ref.watch(currentProjectIdProvider);
  return ref.watch(projectTypeProvider(projectId));
});

/// Convenience: does the current project have [cap]?
bool currentProjectHas(WidgetRef ref, ProjectCapability cap) =>
    ref.watch(currentProjectTypeProvider).has(cap);
