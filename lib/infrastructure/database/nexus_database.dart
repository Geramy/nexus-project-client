// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/database/tables/client.dart';
import '../models/database/tables/project.dart';
import '../models/database/tables/task.dart';
import '../models/database/tables/inference_server.dart';
import '../models/database/tables/agent_persona.dart';
import '../models/database/tables/skill.dart';
import '../models/database/tables/deployment.dart';
import '../models/database/tables/activity_log.dart';
import '../models/database/tables/ci_run.dart';
import '../models/database/tables/ci_job.dart';
import '../models/database/tables/ci_step.dart';
import '../models/database/tables/chat_session.dart';
import '../models/database/tables/chat_message.dart';
import '../models/database/tables/project_tag.dart';
import '../models/database/tables/library_verification.dart';
import '../../features/agents/agent_role.dart';
import '../../features/agents/agent_role_policy.dart';
import '../../features/projects/task_workflow.dart';

part 'nexus_database.g.dart';

/// Database definition using Drift.
///
/// All tables use integer auto-increment primary keys named `<entity>_pk`
/// (client_pk, project_pk, task_pk, agent_pk, server_pk, session_pk, …) and
/// foreign keys named `<ref>_fk` (client_fk, project_fk, task_parent_fk, …).
@DriftDatabase(tables: [Clients, Projects, Tasks, InferenceServers, AgentPersonas, Skills, Deployments, ActivityLogs, CiRuns, CiJobs, CiSteps, ChatSessions, ChatMessages, ProjectTags, LibraryVerifications])
class NexusDatabase extends _$NexusDatabase {
  NexusDatabase() : super(_openConnection()) {
    _initDriftOptions();
  }

  @override
  int get schemaVersion => 25;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) => m.createAll(),
      onUpgrade: (Migrator m, int from, int to) async {
        // From v17 onward we migrate incrementally. v17 moved plans out of the
        // DB into the project workspace (/PLANS files), which re-typed the
        // task/chat plan foreign keys to text paths — a structural change that
        // can't be done with addColumn, so anything below v17 gets a clean
        // reset (no real plan/file data existed yet).
        if (from < 17) {
          for (final table in allTables) {
            await customStatement('DROP TABLE IF EXISTS "${table.actualTableName}"');
          }
          await m.createAll();
          return;
        }
        // v17 → v18: builds/CI grew a runs→jobs→steps hierarchy. Add the two new
        // tables and the new CiRuns columns (kind/backend/commit/paths/error/timing).
        if (from < 18) {
          await m.createTable(ciJobs);
          await m.createTable(ciSteps);
          await m.addColumn(ciRuns, ciRuns.kind);
          await m.addColumn(ciRuns, ciRuns.backend);
          await m.addColumn(ciRuns, ciRuns.commitOid);
          await m.addColumn(ciRuns, ciRuns.dockerfilePath);
          await m.addColumn(ciRuns, ciRuns.imageTag);
          await m.addColumn(ciRuns, ciRuns.workflowPath);
          await m.addColumn(ciRuns, ciRuns.errorText);
          await m.addColumn(ciRuns, ciRuns.startedAt);
        }
        // v18 → v19: tasks grew orchestration/verification fields.
        if (from < 19) {
          await m.addColumn(tasks, tasks.acceptanceCriteria);
          await m.addColumn(tasks, tasks.verification);
          await m.addColumn(tasks, tasks.executionStatus);
          await m.addColumn(tasks, tasks.submissionJson);
          await m.addColumn(tasks, tasks.worker_session_fk);
          await m.addColumn(tasks, tasks.workBranch);
        }
        // v19 → v20: a build/CI run can be attached to a task so a green
        // build/CI auto-completes it (and a red one sends it back).
        if (from < 20) {
          await m.addColumn(ciRuns, ciRuns.task_fk);
        }
        // v20 → v21: projects gained orchestration control (run state +
        // working-hours window) for the autonomous worker-spawn loop.
        if (from < 21) {
          await m.addColumn(projects, projects.orchestrationState);
          await m.addColumn(projects, projects.workHoursEnabled);
          await m.addColumn(projects, projects.workHoursStart);
          await m.addColumn(projects, projects.workHoursEnd);
          await m.addColumn(projects, projects.workDaysMask);
        }
        // v21 → v22: tasks gained per-task build-pipeline config so the
        // orchestrator can run a Docker/CI build gate between verify and merge.
        if (from < 22) {
          await m.addColumn(tasks, tasks.requiresBuild);
          await m.addColumn(tasks, tasks.dockerfilePath);
          await m.addColumn(tasks, tasks.workflowPath);
          await m.addColumn(tasks, tasks.imageTag);
        }
        // v22 → v23: projects can override the orchestrator's prompt templates
        // (worker/verify/merge framing + kickoff text) per project.
        if (from < 23) {
          await m.addColumn(projects, projects.orchestratorPromptsJson);
        }
        // v23 → v24: Project Setup workflow. Projects gain setup/summary fields,
        // plus a structured tag profile (ProjectTags) and a freshness-check cache
        // (LibraryVerifications) for the setup's library/framework research.
        if (from < 24) {
          await m.addColumn(projects, projects.setupStatus);
          await m.addColumn(projects, projects.setupTranscriptJson);
          await m.addColumn(projects, projects.projectSummaryMd);
          await m.addColumn(projects, projects.summaryUpdatedAt);
          await m.createTable(projectTags);
          await m.createTable(libraryVerifications);
        }
        // v24 → v25: library tags can attach to the language they're used with
        // (e.g. a Dart package vs. a C# NuGet), so the board can group them.
        if (from < 25) {
          await m.addColumn(projectTags, projectTags.forLanguage);
        }
      },
    );
  }

  // ==================== Clients ====================
  Future<List<Client>> getAllClients() => select(clients).get();

  Stream<List<Client>> watchAllClients() => (select(clients)
        ..orderBy([
          (c) => OrderingTerm(expression: c.isDefault, mode: OrderingMode.desc),
          (c) => OrderingTerm(expression: c.name),
        ]))
      .watch();

  Future<Client?> getDefaultClient() {
    return (select(clients)..where((c) => c.isDefault.equals(true))).getSingleOrNull();
  }

  /// Inserts a client and returns its new integer pk.
  Future<int> createClient(ClientsCompanion entry) => into(clients).insert(entry);

  /// Deletes a client and all its dependent data.
  Future<bool> deleteClient(int clientPk) async {
    await (delete(deployments)..where((d) => d.client_fk.equals(clientPk))).go();
    await (delete(activityLogs)..where((a) => a.client_fk.equals(clientPk))).go();
    await (delete(ciRuns)..where((c) => c.client_fk.equals(clientPk))).go();
    final projectRows = await (select(projects)..where((p) => p.client_fk.equals(clientPk))).get();
    for (final proj in projectRows) {
      final sessions = await (select(chatSessions)..where((s) => s.project_fk.equals(proj.project_pk))).get();
      for (final s in sessions) {
        await (delete(chatMessages)..where((m) => m.session_fk.equals(s.session_pk))).go();
      }
      await (delete(chatSessions)..where((s) => s.project_fk.equals(proj.project_pk))).go();
      await (delete(tasks)..where((t) => t.task_project_fk.equals(proj.project_pk))).go();
    }
    await (delete(projects)..where((p) => p.client_fk.equals(clientPk))).go();
    await (delete(agentPersonas)..where((p) => p.client_fk.equals(clientPk))).go();
    await (delete(inferenceServers)..where((s) => s.client_fk.equals(clientPk))).go();
    await (delete(skills)..where((s) => s.client_fk.equals(clientPk))).go();
    final result = await (delete(clients)..where((c) => c.client_pk.equals(clientPk))).go();
    return result > 0;
  }

  /// Creates a client and seeds a default Inference Server + starter personas.
  /// Returns the new client pk.
  Future<int> createClientWithDefaults({required String name, bool isDefault = false}) async {
    final clientPk = await createClient(
      ClientsCompanion.insert(name: name, isDefault: Value(isDefault)),
    );

    await createInferenceServer(
      InferenceServersCompanion.insert(
        client_fk: clientPk,
        name: 'Local Lemonade',
        baseUrl: 'http://localhost:13305/v1',
        providerType: const Value('lemonade'),
        maxConcurrency: const Value(4),
        maxAgents: const Value(8),
      ),
    );

    await seedDefaultAgentsAndSkills(clientPk);

    return clientPk;
  }

  /// Seeds the reusable Skill prefabs and the eight default role-based agent
  /// personas (Project Manager, Coordinator, the five SDE workers, and the
  /// Verification Agent). Each persona's title is its [AgentRole.key], and its
  /// tool permissions + skills are derived from the rule engine in
  /// agent_role_policy.dart so they stay consistent with role policy.
  Future<void> seedDefaultAgentsAndSkills(int clientPk) async {
    // Skill prefabs — one row per bundle in the catalog.
    for (final entry in kSkillCatalog.entries) {
      final meta = kSkillMeta[entry.key];
      await createSkill(
        SkillsCompanion.insert(
          client_fk: clientPk,
          name: entry.key,
          description: Value(meta?.description),
          category: Value(meta?.category ?? 'general'),
          riskLevel: Value(meta?.riskLevel ?? 'medium'),
          configJson: Value(jsonEncode({
            'tools': {for (final t in entry.value.entries) t.key: t.value.name},
          })),
          isPrefab: const Value(true),
        ),
      );
    }

    // Role personas — title-driven, permissions + skills from the rule engine.
    for (final role in AgentRole.values) {
      await createAgentPersona(
        AgentPersonasCompanion.insert(
          client_fk: clientPk,
          name: role.displayTitle,
          title: Value(role.key),
          description: Value(role.description),
          capabilitiesJson: Value(jsonEncode(defaultSkillNames(role))),
          configJson: Value(defaultConfigJson(role)),
          isPrefab: const Value(true),
        ),
      );
    }
  }

  Future<int> createSkill(SkillsCompanion entry) => into(skills).insert(entry);

  // ==================== Projects ====================
  Future<List<Project>> getProjectsForClient(int clientPk) {
    return (select(projects)..where((p) => p.client_fk.equals(clientPk))).get();
  }

  Stream<List<Project>> watchProjectsForClient(int clientPk) {
    return (select(projects)..where((p) => p.client_fk.equals(clientPk))).watch();
  }

  Future<int> createProject(ProjectsCompanion entry) => into(projects).insert(entry);

  /// Deletes a project and all its tasks + chat sessions.
  Future<bool> deleteProject(int projectPk) async {
    final sessions = await (select(chatSessions)..where((s) => s.project_fk.equals(projectPk))).get();
    for (final s in sessions) {
      await (delete(chatMessages)..where((m) => m.session_fk.equals(s.session_pk))).go();
    }
    await (delete(chatSessions)..where((s) => s.project_fk.equals(projectPk))).go();
    await (delete(tasks)..where((t) => t.task_project_fk.equals(projectPk))).go();
    final result = await (delete(projects)..where((p) => p.project_pk.equals(projectPk))).go();
    return result > 0;
  }

  /// The agent persona assigned to a project's Coordinator (or null).
  Future<int?> getProjectAgentPersonaId(int projectPk) async {
    final row = await (select(projects)..where((p) => p.project_pk.equals(projectPk))).getSingleOrNull();
    return row?.agent_persona_fk;
  }

  Future<void> setProjectAgentPersona(int projectPk, int? personaPk) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(
      ProjectsCompanion(agent_persona_fk: Value(personaPk)),
    );
  }

  /// Reactive single-project query — the project controls watch this so the
  /// Start/Pause state and working-hours edits reflect immediately.
  Stream<Project?> watchProject(int projectPk) {
    return (select(projects)..where((p) => p.project_pk.equals(projectPk))).watchSingleOrNull();
  }

  /// Set the orchestration run state: 'stopped' | 'running' | 'paused'.
  Future<void> setProjectOrchestrationState(int projectPk, String state) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(
      ProjectsCompanion(orchestrationState: Value(state), updatedAt: Value(DateTime.now())),
    );
  }

  /// Set (or clear) the project's working-hours window. [start]/[end] are
  /// minutes from midnight; [daysMask] is a Mon..Sun weekday bitmask (0 = all).
  Future<void> setProjectWorkingHours(
    int projectPk, {
    required bool enabled,
    int? start,
    int? end,
    int? daysMask,
  }) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(ProjectsCompanion(
      workHoursEnabled: Value(enabled),
      workHoursStart: Value(start),
      workHoursEnd: Value(end),
      workDaysMask: Value(daysMask),
      updatedAt: Value(DateTime.now()),
    ));
  }

  // ==================== Tasks (tree + full provenance) ====================
  Future<List<Task>> getTasksForProject(int projectPk) {
    return (select(tasks)..where((t) => t.task_project_fk.equals(projectPk))).get();
  }

  Future<Project?> getProjectById(int projectPk) {
    return (select(projects)..where((p) => p.project_pk.equals(projectPk))).getSingleOrNull();
  }

  /// Persist a project's orchestrator prompt-template overrides (JSON), or null
  /// to clear all overrides back to the built-in defaults.
  Future<void> setProjectOrchestratorPrompts(int projectPk, String? json) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(
      ProjectsCompanion(
        orchestratorPromptsJson: Value(json),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ==================== Project Setup ====================
  /// Update a project's setup workflow state (notStarted|inProgress|skipped|complete).
  Future<void> setProjectSetupStatus(int projectPk, String status) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(
      ProjectsCompanion(setupStatus: Value(status), updatedAt: Value(DateTime.now())),
    );
  }

  /// Persist the setup interview transcript (JSON), or null to clear it.
  Future<void> setProjectSetupTranscript(int projectPk, String? json) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(
      ProjectsCompanion(setupTranscriptJson: Value(json), updatedAt: Value(DateTime.now())),
    );
  }

  /// Persist the AI-compiled project summary (markdown) + its timestamp.
  Future<void> setProjectSummary(int projectPk, String? markdown) async {
    await (update(projects)..where((p) => p.project_pk.equals(projectPk))).write(
      ProjectsCompanion(
        projectSummaryMd: Value(markdown),
        summaryUpdatedAt: Value(markdown == null ? null : DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ==================== Project Tags ====================
  /// Live tag profile for a project, ordered by category then creation.
  Stream<List<ProjectTag>> watchTagsForProject(int projectPk) {
    return (select(projectTags)
          ..where((t) => t.project_fk.equals(projectPk))
          ..orderBy([
            (t) => OrderingTerm(expression: t.category),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .watch();
  }

  Future<List<ProjectTag>> getTagsForProject(int projectPk) {
    return (select(projectTags)..where((t) => t.project_fk.equals(projectPk))).get();
  }

  /// Insert a tag if (project, category, value) is new; returns the existing or
  /// new row's pk. Keeps the profile free of duplicate values per section.
  /// Wrapped in a transaction so concurrent upserts of the same tag (e.g. the
  /// workspace observer scanning while the AI proposes the same library) can't
  /// interleave their select+insert and produce a duplicate row.
  Future<int> upsertTag(ProjectTagsCompanion entry) async {
    return transaction(() async {
      final existing = await (select(projectTags)
            ..where((t) =>
                t.project_fk.equals(entry.project_fk.value) &
                t.category.equals(entry.category.value) &
                t.value.equals(entry.value.value)))
          .get();
      if (existing.isNotEmpty) {
        final pk = existing.first.tag_pk;
        await (update(projectTags)..where((t) => t.tag_pk.equals(pk))).write(entry);
        return pk;
      }
      return into(projectTags).insert(entry);
    });
  }

  Future<void> setTagStatus(int tagPk, String status) async {
    await (update(projectTags)..where((t) => t.tag_pk.equals(tagPk)))
        .write(ProjectTagsCompanion(status: Value(status)));
  }

  Future<void> deleteTag(int tagPk) async {
    await (delete(projectTags)..where((t) => t.tag_pk.equals(tagPk))).go();
  }

  // ==================== Library verification cache ====================
  /// Cached freshness check for (ecosystem, name), or null if absent.
  Future<LibraryVerification?> getCachedVerification(String ecosystem, String name) {
    return (select(libraryVerifications)
          ..where((v) => v.ecosystem.equals(ecosystem) & v.name.equals(name)))
        .getSingleOrNull();
  }

  /// Insert or replace the cached verification for (ecosystem, name). Wrapped in
  /// a transaction so concurrent verifications of the same package (lookup +
  /// propose) can't both insert and duplicate the cache row.
  Future<void> upsertVerification(LibraryVerificationsCompanion entry) async {
    await transaction(() async {
      final existing = await (select(libraryVerifications)
            ..where((v) =>
                v.ecosystem.equals(entry.ecosystem.value) &
                v.name.equals(entry.name.value)))
          .get();
      if (existing.isNotEmpty) {
        await (update(libraryVerifications)
              ..where(
                  (v) => v.verification_pk.equals(existing.first.verification_pk)))
            .write(entry);
      } else {
        await into(libraryVerifications).insert(entry);
      }
    });
  }

  /// Agent personas available to a project (scoped via its client).
  Future<List<AgentPersona>> getAgentPersonasForProject(int projectPk) async {
    final proj = await getProjectById(projectPk);
    if (proj == null) return const [];
    return getAgentPersonasForClient(proj.client_fk);
  }

  Stream<List<Task>> watchTasksForProject(int projectPk) {
    return (select(tasks)..where((t) => t.task_project_fk.equals(projectPk))).watch();
  }

  /// Watch root tasks (no parent) for a project.
  Stream<List<Task>> watchRootTasksForProject(int projectPk) {
    return (select(tasks)
          ..where((t) => t.task_project_fk.equals(projectPk) & t.task_parent_fk.isNull()))
        .watch();
  }

  /// Tasks generated from a specific plan file (provenance backtrack).
  Future<List<Task>> getTasksForPlanPath(String planPath) {
    return (select(tasks)..where((t) => t.task_plan_path.equals(planPath))).get();
  }

  Future<int> createTask(TasksCompanion entry) => into(tasks).insert(entry);

  /// Create a task with provenance, auto-filling task_client_fk from the project.
  /// This is the preferred creation path so every task can be backtracked.
  Future<int> createTaskInProject({
    required int projectPk,
    required String title,
    int? parentPk,
    String? planPath,
    int? chatSessionPk,
    int? agentPk,
    String description = '',
    String status = 'Todo',
    String priority = 'MED',
  }) async {
    final proj = await (select(projects)..where((p) => p.project_pk.equals(projectPk))).getSingleOrNull();
    final clientPk = proj?.client_fk ?? 0;
    return into(tasks).insert(TasksCompanion.insert(
      task_client_fk: clientPk,
      task_project_fk: projectPk,
      title: title,
      task_parent_fk: parentPk != null ? Value(parentPk) : const Value.absent(),
      task_plan_path: planPath != null ? Value(planPath) : const Value.absent(),
      task_chat_session_fk: chatSessionPk != null ? Value(chatSessionPk) : const Value.absent(),
      task_agent_fk: agentPk != null ? Value(agentPk) : const Value.absent(),
      description: Value(description),
      status: Value(status),
      priority: Value(priority),
    ));
  }

  Future<bool> updateTask(TasksCompanion entry) => update(tasks).replace(entry);

  Future<int> deleteTask(int taskPk) {
    return (delete(tasks)..where((t) => t.task_pk.equals(taskPk))).go();
  }

  /// Partial status update (used by Kanban drag-drop).
  Future<void> updateTaskStatus(int taskPk, String newStatus) async {
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk)))
        .write(TasksCompanion(status: Value(newStatus), updatedAt: Value(DateTime.now())));
  }

  /// Assign (or clear, with null) the agent persona responsible for a task.
  Future<void> assignTaskAgent(int taskPk, int? personaPk) async {
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk)))
        .write(TasksCompanion(task_agent_fk: Value(personaPk), updatedAt: Value(DateTime.now())));
  }

  /// Partial update of a task — only fields present in [patch] change.
  Future<void> patchTask(int taskPk, TasksCompanion patch) async {
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk)))
        .write(patch.copyWith(updatedAt: Value(DateTime.now())));
  }

  /// Set/clear a task's start and/or due dates.
  Future<void> setTaskDates(int taskPk, {Value<DateTime?>? start, Value<DateTime?>? due}) async {
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk))).write(TasksCompanion(
      startDate: start ?? const Value.absent(),
      dueDate: due ?? const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> setTaskBuildConfig(
    int taskPk, {
    Value<bool>? requiresBuild,
    Value<String?>? dockerfilePath,
    Value<String?>? workflowPath,
    Value<String?>? imageTag,
  }) async {
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk))).write(TasksCompanion(
      requiresBuild: requiresBuild ?? const Value.absent(),
      dockerfilePath: dockerfilePath ?? const Value.absent(),
      workflowPath: workflowPath ?? const Value.absent(),
      imageTag: imageTag ?? const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<Task?> getTaskById(int taskPk) async {
    return (select(tasks)..where((t) => t.task_pk.equals(taskPk))).getSingleOrNull();
  }

  // ==================== Orchestration state machine ====================
  // Both the kanban [status] and the orchestration [executionStatus] advance
  // together via [applyEvent] (task_workflow.dart), the single source of truth
  // for transitions. These helpers persist the resulting pair plus any
  // event-specific fields (assigned worker session, branch, submission, etc.).

  /// Persist the (status, executionStatus) a [TaskEvent] produces, merging any
  /// extra column changes in [extra].
  Future<void> _applyTaskEvent(int taskPk, TaskEvent event, [TasksCompanion? extra]) async {
    final next = applyEvent(event);
    var patch = TasksCompanion(
      status: Value(next.status),
      executionStatus: Value(next.exec),
      updatedAt: Value(DateTime.now()),
    );
    if (extra != null) {
      patch = patch.copyWith(
        task_agent_fk: extra.task_agent_fk,
        worker_session_fk: extra.worker_session_fk,
        workBranch: extra.workBranch,
        submissionJson: extra.submissionJson,
        acceptanceCriteria: extra.acceptanceCriteria,
        verification: extra.verification,
      );
    }
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk))).write(patch);
  }

  /// A worker session was spawned and is now executing the task on [workBranch].
  Future<void> markTaskRunning(int taskPk, {required int workerSessionPk, String? workBranch}) {
    return _applyTaskEvent(taskPk, TaskEvent.startWork, TasksCompanion(
      worker_session_fk: Value(workerSessionPk),
      workBranch: workBranch != null ? Value(workBranch) : const Value.absent(),
    ));
  }

  /// The worker called submit_for_completion; store its submission payload.
  Future<void> submitTaskForCompletion(int taskPk, {required String submissionJson}) {
    return _applyTaskEvent(taskPk, TaskEvent.submit, TasksCompanion(
      submissionJson: Value(submissionJson),
    ));
  }

  /// The Verification Agent began running the proof.
  Future<void> markTaskVerifying(int taskPk) {
    return _applyTaskEvent(taskPk, TaskEvent.beginVerify);
  }

  /// Record the verifier's verdict. On pass the task waits for the Coordinator
  /// to merge; on fail it returns to the board for the same agent to re-engage.
  Future<void> recordTaskVerdict(int taskPk, {required bool passed}) {
    return _applyTaskEvent(taskPk, passed ? TaskEvent.verdictPass : TaskEvent.verdictFail);
  }

  /// The Coordinator merged the branch — task is fully done. Clears the live
  /// worker session so its (ephemeral) context can be torn down.
  Future<void> approveTask(int taskPk) {
    return _applyTaskEvent(taskPk, TaskEvent.approve, const TasksCompanion(
      worker_session_fk: Value(null),
    ));
  }

  /// Send a task back to the board (PM/Coordinator reject), clearing its live
  /// worker session and submission.
  Future<void> reopenTask(int taskPk) {
    return _applyTaskEvent(taskPk, TaskEvent.reject, const TasksCompanion(
      worker_session_fk: Value(null),
      submissionJson: Value(null),
    ));
  }

  /// Pipeline build gate started running on this task.
  Future<void> beginTaskBuild(int taskPk) {
    return _applyTaskEvent(taskPk, TaskEvent.beginBuild);
  }

  /// Record the pipeline build gate's outcome: green advances the task to
  /// `built` (awaiting merge); red sends it back to the board for rework.
  Future<void> recordTaskBuildOutcome(int taskPk, {required bool passed}) {
    return _applyTaskEvent(taskPk, passed ? TaskEvent.buildPass : TaskEvent.buildFail);
  }

  /// The Coordinator started merging this task's branch into main.
  Future<void> beginTaskMerge(int taskPk) {
    return _applyTaskEvent(taskPk, TaskEvent.beginMerge);
  }

  /// Apply an attached build/CI run's result to its task: a green run approves
  /// the task (→ Done, worker released); a red run sends it back to the board
  /// (→ Todo) so the same agent re-engages. This is the auto-Done-on-CI rule
  /// for ad-hoc (human/Coordinator-triggered) builds — the autonomous pipeline
  /// instead uses [recordTaskBuildOutcome] so a green build flows into merge.
  Future<void> recordTaskBuildResult(int taskPk, {required bool passed}) async {
    final t = await getTaskById(taskPk);
    if (t == null) return;
    if (passed) {
      await approveTask(taskPk);
    } else {
      await _applyTaskEvent(taskPk, TaskEvent.verdictFail);
    }
  }

  /// Set the Project-Manager-authored definition of done and the runnable proof
  /// the Verification Agent will execute.
  Future<void> setTaskAcceptance(int taskPk, {String? acceptanceCriteria, String? verification}) async {
    await (update(tasks)..where((t) => t.task_pk.equals(taskPk))).write(TasksCompanion(
      acceptanceCriteria: acceptanceCriteria != null ? Value(acceptanceCriteria) : const Value.absent(),
      verification: verification != null ? Value(verification) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  // ==================== Inference Servers (AI Providers) ====================
  Future<List<InferenceServer>> getInferenceServersForClient(int clientPk) {
    return (select(inferenceServers)..where((s) => s.client_fk.equals(clientPk))).get();
  }

  Stream<List<InferenceServer>> watchInferenceServersForClient(int clientPk) {
    return (select(inferenceServers)..where((s) => s.client_fk.equals(clientPk))).watch();
  }

  Future<int> createInferenceServer(InferenceServersCompanion entry) => into(inferenceServers).insert(entry);

  Future<bool> updateInferenceServer(InferenceServersCompanion entry) => update(inferenceServers).replace(entry);

  Future<int> deleteInferenceServer(int serverPk) {
    return (delete(inferenceServers)..where((s) => s.server_pk.equals(serverPk))).go();
  }

  Future<void> updateInferenceServerSelectedModel(int serverPk, String? modelId) async {
    await (update(inferenceServers)..where((s) => s.server_pk.equals(serverPk)))
        .write(InferenceServersCompanion(selectedModel: Value(modelId)));
  }

  Future<void> updateInferenceServerAvailableModels(int serverPk, List<String> models) async {
    await (update(inferenceServers)..where((s) => s.server_pk.equals(serverPk)))
        .write(InferenceServersCompanion(availableModelsJson: Value(json.encode(models))));
  }

  // ==================== Agent Personas ====================
  Future<List<AgentPersona>> getAgentPersonasForClient(int clientPk) {
    return (select(agentPersonas)..where((p) => p.client_fk.equals(clientPk))).get();
  }

  Stream<List<AgentPersona>> watchAgentPersonasForClient(int clientPk) {
    return (select(agentPersonas)..where((p) => p.client_fk.equals(clientPk))).watch();
  }

  Future<int> createAgentPersona(AgentPersonasCompanion entry) => into(agentPersonas).insert(entry);

  Future<bool> updateAgentPersona(AgentPersonasCompanion entry) => update(agentPersonas).replace(entry);

  Future<int> deleteAgentPersona(int agentPk) {
    return (delete(agentPersonas)..where((p) => p.agent_pk.equals(agentPk))).go();
  }

  Future<AgentPersona?> resolveAgentPersona(int agentPk) async {
    return (select(agentPersonas)..where((p) => p.agent_pk.equals(agentPk))).getSingleOrNull();
  }

  // ==================== Deployments (placeholder) ====================
  Future<List<Deployment>> getDeploymentsForClient(int clientPk) {
    return (select(deployments)..where((d) => d.client_fk.equals(clientPk))).get();
  }

  Stream<List<Deployment>> watchDeploymentsForClient(int clientPk) {
    return (select(deployments)..where((d) => d.client_fk.equals(clientPk))).watch();
  }

  Future<int> createDeployment(DeploymentsCompanion entry) => into(deployments).insert(entry);

  // ==================== Coordinator Chat Sessions ====================
  Stream<List<ChatSession>> watchChatSessionsForProject(int projectPk) {
    return (select(chatSessions)
          ..where((s) => s.project_fk.equals(projectPk))
          ..orderBy([(s) => OrderingTerm(expression: s.updatedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  Future<List<ChatSession>> getChatSessionsForProject(int projectPk) {
    return (select(chatSessions)
          ..where((s) => s.project_fk.equals(projectPk))
          ..orderBy([(s) => OrderingTerm(expression: s.updatedAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Inserts a session and returns its new integer pk.
  Future<int> createChatSession(ChatSessionsCompanion entry) => into(chatSessions).insert(entry);

  /// Resolves the chat session for a project — and, when [planPath] is given, the
  /// session tied to that specific plan file (creating one if none exists yet).
  /// This keeps a plan's conversation distinct from the general project chat and
  /// records the plan link so work can be backtracked to it. Returns its pk.
  Future<int> getOrCreateChatSession(int projectPk, {String? planPath}) async {
    final query = select(chatSessions)..where((s) => s.project_fk.equals(projectPk));
    query.where((s) => planPath == null ? s.plan_path.isNull() : s.plan_path.equals(planPath));
    query.orderBy([(s) => OrderingTerm(expression: s.updatedAt, mode: OrderingMode.desc)]);
    final existing = await query.get();
    if (existing.isNotEmpty) return existing.first.session_pk;
    return createChatSession(ChatSessionsCompanion.insert(
      project_fk: projectPk,
      plan_path: planPath != null ? Value(planPath) : const Value.absent(),
    ));
  }

  Future<void> touchChatSession(int sessionPk, {String? title}) async {
    await (update(chatSessions)..where((s) => s.session_pk.equals(sessionPk))).write(
      ChatSessionsCompanion(
        updatedAt: Value(DateTime.now()),
        title: title != null ? Value(title) : const Value.absent(),
      ),
    );
  }

  Future<bool> deleteChatSession(int sessionPk) async {
    await (delete(chatMessages)..where((m) => m.session_fk.equals(sessionPk))).go();
    final r = await (delete(chatSessions)..where((s) => s.session_pk.equals(sessionPk))).go();
    return r > 0;
  }

  Stream<List<ChatMessage>> watchChatMessagesForSession(int sessionPk) {
    return (select(chatMessages)
          ..where((m) => m.session_fk.equals(sessionPk))
          ..orderBy([(m) => OrderingTerm(expression: m.seq), (m) => OrderingTerm(expression: m.createdAt)]))
        .watch();
  }

  Future<List<ChatMessage>> getChatMessagesForSession(int sessionPk) {
    return (select(chatMessages)
          ..where((m) => m.session_fk.equals(sessionPk))
          ..orderBy([(m) => OrderingTerm(expression: m.seq), (m) => OrderingTerm(expression: m.createdAt)]))
        .get();
  }

  Future<int> countChatMessages(int sessionPk) async {
    final rows = await (select(chatMessages)..where((m) => m.session_fk.equals(sessionPk))).get();
    return rows.length;
  }

  /// Inserts a chat message and returns its message_pk.
  Future<int> addChatMessage(ChatMessagesCompanion entry) => into(chatMessages).insert(entry);

  /// Removes a single chat message (used to drop a failed turn's user message
  /// so it can't reload as orphaned, role-breaking history).
  Future<void> deleteChatMessage(int messagePk) =>
      (delete(chatMessages)..where((m) => m.message_pk.equals(messagePk))).go();

  // ==================== Activity Logs (placeholder) ====================
  Future<List<ActivityLog>> getActivityLogsForClient(int clientPk) {
    return (select(activityLogs)..where((a) => a.client_fk.equals(clientPk))).get();
  }

  Stream<List<ActivityLog>> watchActivityLogsForClient(int clientPk) {
    return (select(activityLogs)..where((a) => a.client_fk.equals(clientPk))).watch();
  }

  Future<int> createActivityLog(ActivityLogsCompanion entry) => into(activityLogs).insert(entry);

  // ==================== CI / Build Runs ====================
  Future<List<CiRun>> getCiRunsForClient(int clientPk) {
    return (select(ciRuns)
          ..where((c) => c.client_fk.equals(clientPk))
          ..orderBy([(c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Stream<List<CiRun>> watchCiRunsForClient(int clientPk) {
    return (select(ciRuns)
          ..where((c) => c.client_fk.equals(clientPk))
          ..orderBy([(c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  Stream<List<CiRun>> watchCiRunsForProject(int projectPk) {
    return (select(ciRuns)
          ..where((c) => c.project_fk.equals(projectPk))
          ..orderBy([(c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  Future<CiRun?> getCiRun(int runPk) =>
      (select(ciRuns)..where((c) => c.ci_run_pk.equals(runPk))).getSingleOrNull();

  Stream<CiRun?> watchCiRun(int runPk) =>
      (select(ciRuns)..where((c) => c.ci_run_pk.equals(runPk))).watchSingleOrNull();

  Future<int> createCiRun(CiRunsCompanion entry) => into(ciRuns).insert(entry);

  Future<void> patchCiRun(int runPk, CiRunsCompanion patch) async {
    await (update(ciRuns)..where((c) => c.ci_run_pk.equals(runPk))).write(patch);
  }

  /// Removes a run and its full jobs→steps subtree.
  Future<bool> deleteCiRun(int runPk) async {
    final jobs = await (select(ciJobs)..where((j) => j.ci_run_fk.equals(runPk))).get();
    for (final j in jobs) {
      await (delete(ciSteps)..where((s) => s.ci_job_fk.equals(j.ci_job_pk))).go();
    }
    await (delete(ciJobs)..where((j) => j.ci_run_fk.equals(runPk))).go();
    final r = await (delete(ciRuns)..where((c) => c.ci_run_pk.equals(runPk))).go();
    return r > 0;
  }

  // ==================== CI Jobs ====================
  Future<List<CiJob>> getCiJobsForRun(int runPk) {
    return (select(ciJobs)
          ..where((j) => j.ci_run_fk.equals(runPk))
          ..orderBy([(j) => OrderingTerm(expression: j.orderIndex)]))
        .get();
  }

  Stream<List<CiJob>> watchCiJobsForRun(int runPk) {
    return (select(ciJobs)
          ..where((j) => j.ci_run_fk.equals(runPk))
          ..orderBy([(j) => OrderingTerm(expression: j.orderIndex)]))
        .watch();
  }

  Future<int> createCiJob(CiJobsCompanion entry) => into(ciJobs).insert(entry);

  Future<void> patchCiJob(int jobPk, CiJobsCompanion patch) async {
    await (update(ciJobs)..where((j) => j.ci_job_pk.equals(jobPk))).write(patch);
  }

  // ==================== CI Steps ====================
  Future<List<CiStep>> getCiStepsForJob(int jobPk) {
    return (select(ciSteps)
          ..where((s) => s.ci_job_fk.equals(jobPk))
          ..orderBy([(s) => OrderingTerm(expression: s.orderIndex)]))
        .get();
  }

  Stream<List<CiStep>> watchCiStepsForJob(int jobPk) {
    return (select(ciSteps)
          ..where((s) => s.ci_job_fk.equals(jobPk))
          ..orderBy([(s) => OrderingTerm(expression: s.orderIndex)]))
        .watch();
  }

  Future<int> createCiStep(CiStepsCompanion entry) => into(ciSteps).insert(entry);

  Future<void> patchCiStep(int stepPk, CiStepsCompanion patch) async {
    await (update(ciSteps)..where((s) => s.ci_step_pk.equals(stepPk))).write(patch);
  }

  /// Appends a chunk of captured output to a step's running log.
  Future<void> appendCiStepLog(int stepPk, String chunk) async {
    final row = await (select(ciSteps)..where((s) => s.ci_step_pk.equals(stepPk))).getSingleOrNull();
    if (row == null) return;
    await (update(ciSteps)..where((s) => s.ci_step_pk.equals(stepPk)))
        .write(CiStepsCompanion(logText: Value(row.logText + chunk)));
  }
}

// Helper to suppress noisy Drift multiple-DB warning in debug during heavy development.
void _initDriftOptions() {
  if (kDebugMode) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }
}

/// Platform-specific database connection
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'nexus_projects.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
