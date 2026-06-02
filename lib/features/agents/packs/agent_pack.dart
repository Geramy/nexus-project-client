// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import '../agent_role.dart';
import '../agent_role_policy.dart';

/// One agent provisioned by an [AgentPack]. Plain data (no Flutter imports) so
/// the database layer can seed personas from it without depending on the UI.
///
/// [title] is the persona's stored `title` — for software roles this is the
/// [AgentRole.key] so the orchestration engine can resolve the role; for other
/// domains it's a stable slug. [skills] are names from `kSkillCatalog`, and
/// [configJson] is the precomputed tool-permission map derived from them.
class PackAgent {
  final String name;
  final String title;
  final String description;
  final List<String> skills;
  final String configJson;

  const PackAgent({
    required this.name,
    required this.title,
    required this.description,
    required this.skills,
    required this.configJson,
  });

  /// Build a pack agent from a canonical [AgentRole], reusing the role engine's
  /// default skills + tool permissions so these agents are fully orchestration-
  /// backed (spawn → submit → verify → merge).
  factory PackAgent.fromRole(AgentRole role) => PackAgent(
        name: role.displayTitle,
        title: role.key,
        description: role.description,
        skills: defaultSkillNames(role),
        configJson: defaultConfigJson(role),
      );

  /// Build a pack agent for a non-role domain from an explicit skill list. The
  /// tool-permission map is derived from [skills] via the same default-deny
  /// engine the roles use.
  factory PackAgent.fromSkills({
    required String name,
    required String title,
    required String description,
    required List<String> skills,
  }) =>
      PackAgent(
        name: name,
        title: title,
        description: description,
        skills: skills,
        configJson: configJsonForSkills(skills),
      );
}
