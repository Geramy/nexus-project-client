// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:nexus_projects_client/features/agents/agent_role.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';

/// Picks the default worker persona to assign when a task is created without an
/// explicit owner, so the coordinator never leaves a task unassigned (an
/// unassigned task is invisible to the orchestrator and never gets worked).
///
/// Preference order: an SDE Generalist, then any other worker-role persona,
/// then any persona at all as a last resort. Returns null only when the project
/// has no agent personas whatsoever.
Future<int?> resolveDefaultWorkerPersonaId(
  NexusDatabase db,
  int projectId,
) async {
  final agents = await db.getAgentPersonasForProject(projectId);
  if (agents.isEmpty) return null;

  int? generalist;
  int? anyWorker;
  for (final a in agents) {
    final role = agentRoleFromKey(a.title);
    if (role == AgentRole.sdeGeneralist) {
      generalist ??= a.agent_pk;
    }
    if (role != null && role.isWorker) {
      anyWorker ??= a.agent_pk;
    }
  }
  return generalist ?? anyWorker ?? agents.first.agent_pk;
}

/// Picks a worker persona suited to a task's [layer] ("client" | "server" |
/// "db" | "other"), so the per-story task generator routes UI work to a UI/UX
/// engineer, schema work to a database engineer, etc. — when such a specialist
/// persona exists on the project. Falls back to [fallback] (the run's default
/// worker) when no specialist is present, so routing is best-effort and never
/// leaves a task unassigned.
Future<int?> resolveWorkerPersonaForLayer(
  NexusDatabase db,
  int projectId,
  String? layer, {
  required int? fallback,
}) async {
  final preferred = switch ((layer ?? '').trim().toLowerCase()) {
    'client' || 'ui' || 'frontend' => AgentRole.sdeUiUx,
    'db' || 'database' || 'data' => AgentRole.sdeDatabase,
    'server' || 'backend' || 'api' || 'network' => AgentRole.sdeNetworking,
    'devops' || 'ci' || 'infra' => AgentRole.sdeDevOps,
    _ => null,
  };
  if (preferred == null) return fallback;

  final agents = await db.getAgentPersonasForProject(projectId);
  for (final a in agents) {
    if (agentRoleFromKey(a.title) == preferred) return a.agent_pk;
  }
  return fallback;
}
