// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// Proves the UserStories tree data model used by the post-setup Exploration
// phase: a story tree (epic → stories → sub-story), the task↔story backlink,
// position persistence, patching, and cascading delete.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/features/projects/exploration/exploration_session.dart';
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

  test('generate tasks from stories: one task per LEAF, linked + orchestrating',
      () async {
    final epic = await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        title: 'Tasks',
        kind: const Value('epic'),
      ),
    );
    final leafA = await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        parent_story_fk: Value(epic),
        title: 'Create a task',
        narrative: const Value('As a user, I want to add a task.'),
        acceptanceCriteria: const Value('- shows in the list'),
      ),
    );
    final leafB = await db.createUserStory(
      UserStoriesCompanion.insert(
        project_fk: projectId,
        parent_story_fk: Value(epic),
        title: 'Mark a task done',
      ),
    );

    // No tasks before generation.
    expect(await db.getTasksForProject(projectId), isEmpty);

    final n = await generateTasksFromStories(db, projectId);

    // One task per LEAF story (the epic, which has children, is NOT a task).
    expect(n, 2);
    final tasks = await db.getTasksForProject(projectId);
    expect(tasks.length, 2);
    expect(tasks.map((t) => t.task_story_fk).toSet(), {leafA, leafB});
    // The acceptance criteria rode along into the task description.
    final a = (await db.getTasksForStory(leafA)).single;
    expect(a.description, contains('shows in the list'));

    // The project left Exploration and orchestration is running.
    final proj = await db.getProjectById(projectId);
    expect(proj!.explorationStatus, 'complete');
    expect(proj.orchestrationState, 'running');
  });
}
