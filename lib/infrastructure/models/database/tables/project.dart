// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';
import 'agent_persona.dart';

/// Projects table - belongs to a Client
class Projects extends Table {
  IntColumn get project_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get description => text().nullable()();

  /// Optional reference to an Agent Persona used for this project's Coordinator.
  IntColumn get agent_persona_fk =>
      integer().nullable().references(AgentPersonas, #agent_pk)();

  // ==================== Orchestration control ====================
  /// Whether the autonomous worker-spawn loop is running for this project:
  /// `stopped` (idle, no agents spawned), `running` (actively picking up
  /// assigned tasks), or `paused` (loop suspended, resumable). The Start/Pause
  /// controls on the project drive this.
  TextColumn get orchestrationState =>
      text().withDefault(const Constant('stopped'))();

  /// When true, the loop only spawns workers inside the configured working
  /// hours window; outside it the loop idles even while `running`.
  BoolColumn get workHoursEnabled =>
      boolean().withDefault(const Constant(false))();

  /// Working-hours window as minutes from midnight (local time), e.g. 540 = 09:00.
  /// Null when unset. If start > end the window wraps past midnight.
  IntColumn get workHoursStart => integer().nullable()();
  IntColumn get workHoursEnd => integer().nullable()();

  /// Bitmask of allowed weekdays (bit 0 = Monday … bit 6 = Sunday). 0/null = every day.
  IntColumn get workDaysMask => integer().nullable()();

  /// Per-project overrides for the orchestrator's prompt templates (the framing
  /// + kickoff text wrapped around each role's [defaultSystemPrompt]). JSON map
  /// of template-key → string; absent keys fall back to the built-in defaults.
  /// Null/empty = use defaults for everything.
  TextColumn get orchestratorPromptsJson => text().nullable()();

  // ==================== Project Setup ====================
  /// Setup workflow state: notStarted | inProgress | skipped | complete. A new
  /// project starts at notStarted and is gated to the Setup tab until the user
  /// finishes or skips.
  TextColumn get setupStatus =>
      text().withDefault(const Constant('notStarted'))();

  /// The setup interview Q/A transcript (JSON) so decisions can be re-explained.
  TextColumn get setupTranscriptJson => text().nullable()();

  /// Post-setup **Exploration** phase state: none | active | complete. After
  /// setup finishes the project enters `active` — a discovery chat that builds
  /// the user-story tree — and stays there (NO tasks generated) until the user
  /// presses "Generate tasks from stories", which flips it to `complete`.
  TextColumn get explorationStatus =>
      text().withDefault(const Constant('none'))();

  // ==================== Templater / milestones ====================
  /// The Templater (pre-task) phase state: `none` (not applicable / legacy),
  /// `pending` (tasks generated, base not yet scaffolded), `scaffolding` (the
  /// Coordinator is building the base project + task stubs), `ready` (base
  /// committed & CI-green — workers may start), or `failed`. Workers are gated
  /// until this is `ready`, which is what stops every agent from racing to
  /// scaffold an empty `main` at once.
  TextColumn get templateStatus =>
      text().withDefault(const Constant('none'))();

  /// The milestone batch currently open for work (0-based). Workers only pick up
  /// tasks whose `milestoneOrder` equals this; when that batch finishes and its
  /// CI is green, the orchestrator advances it until it reaches [milestoneCount].
  IntColumn get currentMilestone => integer().withDefault(const Constant(0))();

  /// Total number of milestone batches the Templater split the backlog into
  /// (1 = no intermediate milestones: base → all tasks → final CI). 0 until the
  /// Templater runs.
  IntColumn get milestoneCount => integer().withDefault(const Constant(0))();

  /// AI-compiled, human-readable summary of the project (markdown), built from
  /// all /PLANS files. Regenerated on plan changes and by the coordinator's
  /// idle cycles. Null until first generated.
  TextColumn get projectSummaryMd => text().nullable()();
  DateTimeColumn get summaryUpdatedAt => dateTime().nullable()();

  // ==================== Project type (extensibility) ====================
  /// The project type key from the ProjectType catalog (e.g.
  /// 'application-development', 'project-coordination', 'ivr-call-systems').
  /// Drives which capabilities/UI are shown. Defaults to application-development
  /// so existing projects are unchanged.
  TextColumn get projectType =>
      text().withDefault(const Constant('application-development'))();

  /// Optional sub-category within the type (e.g. IVR: 'inboundIvr',
  /// 'outboundCampaign', 'aiVoicebot'). Null = the type's default.
  TextColumn get subCategory => text().nullable()();

  /// Experience mode: 'regular' | 'advanced'. Presentation only — same model.
  TextColumn get experienceMode =>
      text().withDefault(const Constant('regular'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
