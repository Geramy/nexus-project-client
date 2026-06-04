// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Glue for the post-setup Exploration (discovery) phase: builds the discovery
/// Coordinator system prompt from the project's existing setup profile, and
/// turns the resulting user-story tree into linked tasks when the user is ready.
library;

import '../../../infrastructure/database/nexus_database.dart';
import '../agent_assignment.dart';

/// A hidden kickoff (sent as the first turn) so the coordinator speaks first.
const String kDiscoveryAutoOpen =
    'Start the discovery interview now: greet me briefly, reflect what you '
    'already know about the project from setup, and ask your first question.';

/// Builds the discovery system prompt, seeded with the project's setup tags +
/// summary so the coordinator already knows whether it's an app, a game, etc.
Future<String> buildDiscoveryPrompt(
  NexusDatabase db,
  int projectId,
  String projectName,
) async {
  final tags = await db.getTagsForProject(projectId);
  final byCat = <String, List<String>>{};
  for (final t in tags) {
    if (t.status == 'rejected') continue;
    (byCat[t.category] ??= <String>[]).add(t.value);
  }
  String cat(String k) {
    final v = byCat[k] ?? const [];
    return v.isEmpty ? '—' : v.join(', ');
  }

  final proj = await db.getProjectById(projectId);
  final summary = (proj?.projectSummaryMd ?? '').trim();

  return '''
You are the project Coordinator running the post-setup DISCOVERY interview for "$projectName". Setup is done; NO tasks exist yet. Your job is to flesh the idea out into concrete USER STORIES before any work is created.

PROJECT PROFILE (captured during setup):
- Industries: ${cat('industries')}
- Platforms: ${cat('platforms')}
- Objectives: ${cat('objectives')}
- Features: ${cat('features')}
- Databases: ${cat('databases')}
- Services: ${cat('services')}
${summary.isEmpty ? '' : '\nSummary:\n$summary\n'}
Infer from the industry/profile WHAT this is and tailor your questions:
- If it reads like a GAME (e.g. a Gaming industry / genre), ask about the core loop, genre, mechanics, player goals, progression, and win/lose conditions.
- If it's an APPLICATION, ask about the target users, their key workflows, the main screens, and the data involved.

HOW TO RUN THE INTERVIEW:
- Ask ONE focused question at a time and build on the user's answers — have a real conversation, do not interrogate.
- As the idea takes shape, capture each distinct piece as a USER STORY by calling `add_user_story` with a clear title and a narrative in the form "As a <role>, I want <goal>, so that <benefit>", plus acceptance_criteria when known.
- Build a TREE: create epics for big areas, then nest stories and sub-stories under them via `parent_story_id` (epic → story → sub-story). Use multiple stories — break the idea down.
- Call `list_user_stories` to stay grounded; use `update_user_story` to refine titles/narratives/acceptance/status as you learn more.

IMPORTANT — DO NOT BE EAGER:
- You CANNOT and MUST NOT create tasks. There are no task tools here on purpose.
- When the story tree is solid and covers the idea, tell the user it looks ready and that they can press the "Generate tasks from stories" button when they're happy — the tasks are built from these stories.
''';
}

/// Turns the discovery story tree into tasks: each LEAF story becomes a worker
/// task, stamped with its `story_fk` so task ↔ story is traceable both ways.
/// Flips the project out of the Exploration phase and starts orchestration.
/// Returns the number of tasks created.
Future<int> generateTasksFromStories(NexusDatabase db, int projectId) async {
  final stories = await db.getUserStoriesForProject(projectId);
  final parents = <int>{
    for (final s in stories)
      if (s.parent_story_fk != null) s.parent_story_fk!,
  };
  // Leaves = stories with no children (the concrete, buildable items). If the
  // tree is flat, every story is a leaf.
  final leaves = stories.where((s) => !parents.contains(s.story_pk)).toList();
  final worker = await resolveDefaultWorkerPersonaId(db, projectId);

  var created = 0;
  for (final s in leaves) {
    final ac = (s.acceptanceCriteria ?? '').trim();
    final desc = [
      if (s.narrative.trim().isNotEmpty) s.narrative.trim(),
      if (ac.isNotEmpty) '\nAcceptance criteria:\n$ac',
    ].join('\n').trim();
    await db.createTaskInProject(
      projectPk: projectId,
      title: s.title,
      description: desc,
      agentPk: worker,
      storyPk: s.story_pk,
    );
    created++;
  }

  await db.setProjectExplorationStatus(projectId, 'complete');
  if (created > 0) {
    await db.setProjectOrchestrationState(projectId, 'running');
  }
  return created;
}
