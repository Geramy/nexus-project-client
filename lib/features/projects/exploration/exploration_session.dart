// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Glue for the post-setup Exploration (discovery) phase: builds the discovery
/// Coordinator system prompt from the project's existing setup profile, and
/// turns the resulting user-story tree into linked tasks when the user is ready.
library;

import '../../../infrastructure/database/nexus_database.dart';
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

// Task generation from the story tree lives in task_generator.dart
// (TaskGenerator) — it runs a scoped AI session per story to produce 1..N tasks.
