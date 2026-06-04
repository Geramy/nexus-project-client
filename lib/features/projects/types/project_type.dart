// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

/// A capability a project type may declare. The app gates UI surfaces and agent
/// tools by these, so non-software project types never show software machinery.
enum ProjectCapability {
  // Domain-agnostic — on for every type.
  plans,
  tasks,
  agents,
  files,
  diagrams,
  // Software-only.
  git,
  build,
  ci,
  deploy,
  // Call-systems-only.
  callFlow,
  telephony,
  audioPrompts,
}

/// A sub-category within a project type (e.g. IVR → inbound auto-attendant).
class ProjectTypeSubCategory {
  final String key;
  final String name;
  final String description;
  const ProjectTypeSubCategory(this.key, this.name, this.description);
}

/// A selectable project type. Its [capabilities] drive what the app shows; this
/// is the single source of truth for "what does this kind of project involve".
class ProjectType {
  final String key;
  final String name;
  final String tagline;
  final IconData icon;
  final Set<ProjectCapability> capabilities;
  final List<ProjectTypeSubCategory> subCategories;

  /// Agent pack(s) provisioned by default when creating a project of this type.
  final List<String> defaultAgentPackKeys;

  const ProjectType({
    required this.key,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.capabilities,
    this.subCategories = const [],
    this.defaultAgentPackKeys = const ['application-development'],
  });

  bool has(ProjectCapability c) => capabilities.contains(c);
}

/// Capabilities shared by every type.
const Set<ProjectCapability> _baseCaps = {
  ProjectCapability.plans,
  ProjectCapability.tasks,
  ProjectCapability.agents,
  ProjectCapability.files,
  ProjectCapability.diagrams,
};

/// Full software team + the software toolchain (git/build/ci/deploy).
const ProjectType applicationDevelopmentType = ProjectType(
  key: 'application-development',
  name: 'Application Development',
  tagline:
      'Build and ship software — plans, tasks, agents, git, builds, CI, deploy.',
  icon: Icons.terminal,
  capabilities: {
    ..._baseCaps,
    ProjectCapability.git,
    ProjectCapability.build,
    ProjectCapability.ci,
    ProjectCapability.deploy,
  },
  defaultAgentPackKeys: ['application-development'],
);

/// Generic, domain-ambiguous coordination — no software machinery.
const ProjectType projectCoordinationType = ProjectType(
  key: 'project-coordination',
  name: 'Project Coordination',
  tagline: 'Plan, delegate, and track any kind of project — no code toolchain.',
  icon: Icons.hub_outlined,
  capabilities: _baseCaps,
  defaultAgentPackKeys: ['project-coordination'],
);

/// Phone / IVR call systems — call flows, telephony, AI prompt audio. No
/// git/build/ci/deploy.
const ProjectType ivrCallSystemsType = ProjectType(
  key: 'ivr-call-systems',
  name: 'IVR / Call Systems',
  tagline:
      'Design phone systems — call flows, menus, voicebots, prompts & audio.',
  icon: Icons.call_outlined,
  capabilities: {
    ..._baseCaps,
    ProjectCapability.callFlow,
    ProjectCapability.telephony,
    ProjectCapability.audioPrompts,
  },
  subCategories: [
    ProjectTypeSubCategory(
      'inboundIvr',
      'Inbound IVR / Auto-Attendant',
      'Greet callers, route by menu, business hours, voicemail.',
    ),
    ProjectTypeSubCategory(
      'outboundCampaign',
      'Outbound Campaign',
      'Reminders, notifications, and AI outbound calls (consent/TCPA aware).',
    ),
    ProjectTypeSubCategory(
      'aiVoicebot',
      'AI Voicebot',
      'A conversational virtual agent that answers and handles calls.',
    ),
    ProjectTypeSubCategory(
      'callCenter',
      'Call Center / ACD',
      'Queues, agents, and skills-based routing.',
    ),
    ProjectTypeSubCategory(
      'appointmentReminder',
      'Appointment Reminder',
      'Automated reminders with confirm/reschedule (outbound).',
    ),
    ProjectTypeSubCategory(
      'survey',
      'Survey / Data Collection',
      'Collect responses over the phone via DTMF or speech (outbound).',
    ),
  ],
  defaultAgentPackKeys: ['project-coordination'],
);

/// Every project type we ship, in display order.
const List<ProjectType> kProjectTypes = [
  applicationDevelopmentType,
  projectCoordinationType,
  ivrCallSystemsType,
];

const String kDefaultProjectTypeKey = 'application-development';

/// Look up a type by key, falling back to the default for unknown keys (so a
/// legacy/blank `projectType` column resolves to application-development).
ProjectType projectTypeByKey(String? key) => kProjectTypes.firstWhere(
  (t) => t.key == key,
  orElse: () => applicationDevelopmentType,
);
