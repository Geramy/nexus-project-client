// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import 'setup_flow.dart';
import 'setup_flow_catalog.dart';

/// The resolved [SetupFlowDefinition] for a project — the SINGLE source of truth
/// the setup interview prompt AND the Setup board both read, so the steps the AI
/// follows and the sections shown never diverge. Resolves DB (per type+sub-
/// category) → built-in catalog, reacting to the project's type changing.
final setupFlowForProjectProvider =
    FutureProvider.family<SetupFlowDefinition, int>((ref, projectId) async {
      final db = ref.watch(nexusDatabaseProvider);
      // React to the project row (type/sub-category) changing.
      final proj = await ref.watch(_projectRowProvider(projectId).future);
      final type = proj?.projectType ?? 'application-development';
      final sub = proj?.subCategory;
      final json = await db.resolveSetupFlowJson(type, sub);
      if (json != null) {
        try {
          return SetupFlowDefinition.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
      return resolveBuiltinSetupFlow(type, sub);
    });

final _projectRowProvider = StreamProvider.family((ref, int projectId) {
  return ref.watch(nexusDatabaseProvider).watchProject(projectId);
});
