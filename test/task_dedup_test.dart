// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';

/// Guards the duplicate-task fix: re-running setup/plan-sync must never pile up
/// identical tasks (the root cause of the finalize → orchestration loop).
void main() {
  late NexusDatabase db;

  setUp(() => db = NexusDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('createTaskInProject reuses an existing same-title task in a project',
      () async {
    final a = await db.createTaskInProject(projectPk: 1, title: 'Build login');
    final b = await db.createTaskInProject(projectPk: 1, title: 'Build login');
    expect(b, a, reason: 'duplicate title in same project returns existing id');

    // Different project with the same title is allowed (scoped per project).
    final c = await db.createTaskInProject(projectPk: 2, title: 'Build login');
    expect(c, isNot(a));

    final p1 = await db.getTasksForProject(1);
    expect(p1.where((t) => t.title == 'Build login'), hasLength(1));
  });
}
