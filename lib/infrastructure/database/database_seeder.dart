// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';

/// Seeds initial data and guarantees the built-in "Default" client always
/// exists. With integer auto-increment PKs we let the DB assign ids; on a fresh
/// database the Default client becomes client_pk = 1, its project project_pk = 1.
Future<void> seedInitialData(NexusDatabase db) async {
  final existingDefault = await db.getDefaultClient();
  if (existingDefault != null) return; // Already have a Default client.

  int clientPk;
  try {
    // Seeds the Default client + a Local Lemonade server + starter personas.
    clientPk = await db.createClientWithDefaults(name: 'Default', isDefault: true);
  } catch (e) {
    print('Seeder: could not ensure Default client (non-fatal): $e');
    return;
  }

  // Sample project + tasks (best-effort).
  try {
    final projectPk = await db.createProject(ProjectsCompanion.insert(
      client_fk: clientPk,
      name: 'Project',
      description: const Value('Default project'),
    ));

    final masterPk = await db.createTaskInProject(
      projectPk: projectPk,
      title: 'Refactor JWT validation + add refresh token rotation',
      description: 'Master plan for auth improvements',
      status: 'Agent Active',
      priority: 'HIGH',
    );

    await db.createTaskInProject(
      projectPk: projectPk,
      parentPk: masterPk,
      title: 'Design new refresh token flow',
      status: 'Done',
      priority: 'HIGH',
    );

    await db.createTaskInProject(
      projectPk: projectPk,
      parentPk: masterPk,
      title: 'Implement rotation logic + tests',
      status: 'In Progress',
      priority: 'HIGH',
    );
  } catch (e) {
    print('Seeder: sample data warning (non-fatal): $e');
  }
}
