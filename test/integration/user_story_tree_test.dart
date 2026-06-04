// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// Proves the UserStories tree data model used by the post-setup Exploration
// phase: a story tree (epic → stories → sub-story), the task↔story backlink,
// position persistence, patching, and cascading delete.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';

void main() {
  late NexusDatabase db;
  late int projectId;

  setUp(() async {
    db = NexusDatabase.forTesting(NativeDatabase.memory());
    final clientId = await db.createClientWithDefaults(
      name: 'Stories',
      isDefault: true,
    );
    projectId = await db.createProject(
      ProjectsCompanion.insert(
        client_fk: clientId,
        name: 'Story Demo',
        projectType: const Value('application-development'),
      ),
    );
  });

  tearDown(() async => db.close());

  test('builds a story tree, links a task, persists position, cascades delete',
      () async {
    // Epic → 2 stories → 1 sub-story.
    final epic = await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        title: 'Account & auth',
        kind: const Value('epic'),
      ),
    );
    final story1 = await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        parent_story_fk: Value(epic),
        title: 'Sign up',
        narrative: const Value(
          'As a new user, I want to register, so that I can save my tasks.',
        ),
      ),
    );
    await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        parent_story_fk: Value(epic),
        title: 'Log in',
      ),
    );
    final sub = await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        parent_story_fk: Value(story1),
        title: 'Email verification',
        kind: const Value('substory'),
      ),
    );

    // The whole tree is queryable (flat) and the parent links are intact.
    var all = await db.getUserStoriesForProject(projectId);
    expect(all.length, 4);
    expect(all.firstWhere((s) => s.story_pk == sub).parent_story_fk, story1);
    expect(all.firstWhere((s) => s.story_pk == story1).parent_story_fk, epic);

    // Task ↔ story backlink: a task stamped with story1 is found both ways.
    final taskId = await db.createTaskInProject(
      projectPk: projectId,
      title: 'Implement sign-up form',
      storyPk: story1,
    );
    final linked = await db.getTasksForStory(story1);
    expect(linked.map((t) => t.task_pk), contains(taskId));
    expect(linked.single.task_story_fk, story1);

    // Patch + position persistence.
    await db.updateUserStory(
      story1,
      UserStoriesCompanion(status: const Value('confirmed')),
    );
    await db.setUserStoryPosition(story1, 123, 456);
    final fresh = await db.getUserStoryById(story1);
    expect(fresh!.status, 'confirmed');
    expect(fresh.posX, 123);
    expect(fresh.posY, 456);

    // Deleting the epic cascades to every descendant.
    await db.deleteUserStory(epic);
    all = await db.getUserStoriesForProject(projectId);
    expect(all, isEmpty);
  });

  test('task dedup is scoped per-story: same title under two stories both exist',
      () async {
    final storyA = await db.createUserStory(
      UserStoriesCompanion.insert(project_fk: projectId, title: 'Story A'),
    );
    final storyB = await db.createUserStory(
      UserStoriesCompanion.insert(project_fk: projectId, title: 'Story B'),
    );

    // Two DIFFERENT stories each yield a generically-titled task. The second
    // must NOT collapse into the first (which would mis-attribute it).
    final a = await db.createTaskInProject(
      projectPk: projectId,
      title: 'Add database migration',
      acceptanceCriteria: 'Migration applies cleanly on a fresh DB.',
      storyPk: storyA,
    );
    final b = await db.createTaskInProject(
      projectPk: projectId,
      title: 'Add database migration',
      storyPk: storyB,
    );
    expect(a, isNot(b), reason: 'distinct stories → distinct tasks');
    expect((await db.getTasksForStory(storyA)).single.task_pk, a);
    expect((await db.getTasksForStory(storyB)).single.task_pk, b);

    // Acceptance criteria is stamped onto the task (drives the verify gate).
    final ta = await db.getTaskById(a);
    expect(ta!.acceptanceCriteria, 'Migration applies cleanly on a fresh DB.');

    // Within the SAME story, an identical title is still idempotent.
    final aAgain = await db.createTaskInProject(
      projectPk: projectId,
      title: 'Add database migration',
      storyPk: storyA,
    );
    expect(aAgain, a, reason: 're-run within a story collapses to the same task');
  });
}
