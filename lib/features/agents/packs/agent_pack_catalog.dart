// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../agent_role.dart';
import 'agent_pack.dart';

/// A selectable bundle of agents provisioned into a client when a new client or
/// project is created (and during first-run onboarding). "We provide different
/// agent packs" — this catalog is the source of truth for the ones we ship.
///
/// [fullyWired] marks packs whose agents map to canonical [AgentRole]s and are
/// therefore backed by the full orchestration engine (spawn/verify/merge). Other
/// domains can be added as packs over time; until their orchestration is made
/// domain-aware they provision working planning agents but aren't marked wired.
class AgentPack {
  final String key;
  final String name;
  final String tagline;
  final IconData icon;
  final bool fullyWired;
  final List<PackAgent> agents;

  const AgentPack({
    required this.key,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.agents,
    this.fullyWired = false,
  });
}

/// The full software team: planner, integrator, the five SDE specialists, and a
/// verification agent. Maps 1:1 to the canonical roles, so it is fully wired.
final AgentPack applicationDevelopmentPack = AgentPack(
  key: 'application-development',
  name: 'Application Development',
  tagline:
      'A complete software team — Project Manager, Coordinator, SDE specialists, and verification.',
  icon: Icons.terminal,
  fullyWired: true,
  agents: AgentRole.values.map(PackAgent.fromRole).toList(growable: false),
);

/// A general-purpose, domain-ambiguous coordination team: a planner, an
/// integrator, one generalist worker, and verification. Suitable for any kind of
/// project where you want agentic planning + task execution without committing
/// to a specialized software stack.
final AgentPack projectCoordinationPack = AgentPack(
  key: 'project-coordination',
  name: 'Project Coordination',
  tagline:
      'A general-purpose planning team for any project — plan, delegate, verify.',
  icon: Icons.hub_outlined,
  fullyWired: true,
  agents: const [
    AgentRole.projectManager,
    AgentRole.coordinator,
    AgentRole.sdeGeneralist,
    AgentRole.verificationAgent,
  ].map(PackAgent.fromRole).toList(growable: false),
);

/// Every pack we ship, in display order.
final List<AgentPack> kAgentPacks = [
  applicationDevelopmentPack,
  projectCoordinationPack,
];

/// The pack provisioned by default (the built-in Default client, and the
/// pre-selected option in the picker).
const String kDefaultAgentPackKey = 'application-development';

/// Look up a pack by key, falling back to the default pack for unknown keys.
AgentPack agentPackByKey(String key) => kAgentPacks.firstWhere(
  (p) => p.key == key,
  orElse: () => applicationDevelopmentPack,
);

/// The de-duplicated union of agents across the given pack keys. Agents are
/// keyed by [PackAgent.title], so selecting overlapping packs (e.g. both ship a
/// Project Manager) provisions each role once.
List<PackAgent> agentsForPackKeys(Iterable<String> keys) {
  final seen = <String>{};
  final out = <PackAgent>[];
  for (final key in keys) {
    for (final agent in agentPackByKey(key).agents) {
      if (seen.add(agent.title)) out.add(agent);
    }
  }
  return out;
}
