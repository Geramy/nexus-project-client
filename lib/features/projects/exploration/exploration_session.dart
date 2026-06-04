// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Glue for the post-setup Exploration (discovery) phase: builds the discovery
/// Coordinator system prompt from the project's existing setup profile, and
/// turns the resulting user-story tree into linked tasks when the user is ready.
library;

import '../../../infrastructure/database/nexus_database.dart';
import '../agent_assignment.dart';
import '../orchestration/orchestrator_prompts.dart';

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

  // The discovery system prompt is a SYSTEM SETTING (editable in the Prompts
  // tab, per project) — the hierarchy/chaining behavior lives there, not buried
  // in code. We append the dynamic project profile so it's grounded.
  final instructions = OrchestratorPrompts.fromJson(proj?.orchestratorPromptsJson)
      .raw(OrchestratorPromptField.discoverySystem)
      .replaceAll('{projectName}', projectName);

  return '''
$instructions

PROJECT PROFILE (captured during setup):
- Industries: ${cat('industries')}
- Platforms: ${cat('platforms')}
- Objectives: ${cat('objectives')}
- Features: ${cat('features')}
- Databases: ${cat('databases')}
- Services: ${cat('services')}
${summary.isEmpty ? '' : '\nSummary:\n$summary\n'}
Tailor your questions to this profile: if the industry/genre reads like a GAME, ask about the core loop, mechanics, progression, and win/lose; if an APPLICATION, ask about the target users, their key workflows, the main screens, and the data involved.''';
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
