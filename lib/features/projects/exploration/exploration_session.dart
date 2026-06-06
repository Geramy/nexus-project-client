// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Glue for the post-setup Exploration (discovery) phase: builds the discovery
/// Coordinator system prompt from the project's existing setup profile, and
/// turns the resulting user-story tree into linked tasks when the user is ready.
library;

import '../../../infrastructure/database/nexus_database.dart';
import '../orchestration/orchestrator_prompts.dart';
import '../project_baseline.dart';

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
  final proj = await db.getProjectById(projectId);

  // The discovery system prompt is a SYSTEM SETTING (editable in the Prompts
  // tab, per project) — the hierarchy/chaining behavior lives there, not buried
  // in code. We append the full, AUTHORITATIVE project baseline (every setup
  // decision incl. languages/frameworks/libraries) so discovery is grounded and
  // can't drift the stack — instead of the old partial profile that dropped the
  // tech stack and let stories invent a different one (e.g. a web app becoming a
  // Unity/C# game).
  final instructions = OrchestratorPrompts.fromJson(proj?.orchestratorPromptsJson)
      .raw(OrchestratorPromptField.discoverySystem)
      .replaceAll('{projectName}', projectName);
  final baseline = await buildProjectBaseline(db, projectId);

  return '''
$instructions

$baseline

Tailor your questions to this baseline: if the industry/genre reads like a GAME, ask about the core loop, mechanics, progression, and win/lose; if an APPLICATION, ask about the target users, their key workflows, the main screens, and the data involved. Every story you create must be buildable within the platforms and stack above.''';
}

// Task generation from the story tree lives in task_generator.dart
// (TaskGenerator) — it runs a scoped AI session per story to produce 1..N tasks.
