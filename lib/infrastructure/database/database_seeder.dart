// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/foundation.dart';

import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';

/// Seeds initial data and guarantees the built-in "Default" client always
/// exists. With integer auto-increment PKs we let the DB assign ids; on a fresh
/// database the Default client becomes client_pk = 1.
///
/// We intentionally do NOT seed a sample project or tasks: the first-run
/// onboarding wizard walks the user through creating their real first project
/// (and picking an agent pack), so a fresh install starts clean instead of with
/// a confusing placeholder project.
Future<void> seedInitialData(NexusDatabase db) async {
  // Configurable setup-interview flows are global + idempotent — seed them
  // every launch (independent of the Default-client check below) so new built-in
  // flows (e.g. new IVR sub-categories) appear without a DB reset.
  try {
    await db.seedSetupFlows();
  } catch (e) {
    debugPrint('Seeder: setup flows warning (non-fatal): $e');
  }

  final existingDefault = await db.getDefaultClient();
  if (existingDefault != null) return; // Already have a Default client.

  try {
    // Seeds the Default client + a Local Lemonade server + skill prefabs + the
    // default agent pack (Application Development).
    await db.createClientWithDefaults(name: 'Default', isDefault: true);
  } catch (e) {
    debugPrint('Seeder: could not ensure Default client (non-fatal): $e');
  }
}
