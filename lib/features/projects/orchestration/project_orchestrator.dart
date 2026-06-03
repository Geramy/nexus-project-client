// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend_factory.dart' show backendForServer;
import 'package:nexus_projects_client/infrastructure/inference/routed_server.dart' show isRoutedProviderType;
import 'package:nexus_projects_client/infrastructure/inference/inference_client.dart' show InferenceBackend;
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart' as ui_server;
import 'package:nexus_projects_client/infrastructure/workspace/workspace.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/git_engine_provider.dart';
import 'package:nexus_projects_client/infrastructure/build/build_models.dart' show CiStatus, CiStatusX;
import 'package:nexus_projects_client/infrastructure/build/build_service.dart';
import 'package:nexus_projects_client/infrastructure/build/build_service_provider.dart';
import 'package:nexus_projects_client/features/agents/thinking_mode.dart';
import 'package:nexus_projects_client/features/agents/agent_role.dart';
import 'package:nexus_projects_client/features/agents/agent_role_policy.dart';
import 'package:nexus_projects_client/features/agents/agent_tool_permissions.dart';
import 'package:nexus_projects_client/features/projects/coordinator_session.dart';
import 'package:nexus_projects_client/features/projects/orchestration/orchestrator_prompts.dart';
import 'package:nexus_projects_client/features/projects/project_working_hours.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';

/// Live driver for a project's autonomous task pipeline.
///
/// It watches the project's `orchestrationState` (Start/Pause/Stop) and the
/// working-hours window. While the project is `running` and inside its hours,
/// it advances tasks through the full pipeline, one unit of work per loop:
///   1. **Implement** — an assigned worker task on the board gets an ephemeral
///      worker session on branch `task/<id>`, driven to `submit_for_completion`.
///   2. **Verify** — a submitted task gets an ephemeral Verification Agent that
///      runs the task's verification and emits a pass/fail verdict.
///   3. **Build** — a verified task that `requiresBuild` is built/CI'd directly
///      by the orchestrator (no LLM); the result advances it to `built` or back
///      to the board. Tasks without a build gate skip straight to merge.
///   4. **Merge** — a merge-ready task (built, or verified without a build gate)
///      gets an ephemeral Coordinator that merges the task's work branch into
///      its integration target (the parent task's branch for a subtask,
///      otherwise main) and approves the task to Done.
///
/// Stages that need an agent degrade gracefully: if no Verification Agent or
/// Coordinator persona exists for the client, the task is left in place.
///
/// One orchestrator exists per project (via [projectOrchestratorProvider]); it
/// processes tasks sequentially to avoid agents fighting over the workspace.
class ProjectOrchestrator {
  final Ref ref;
  final int projectId;

  StreamSubscription<Project?>? _projectSub;
  Timer? _ticker;

  /// True while [_pump] is actively walking the task queue, so overlapping
  /// triggers (state change + ticker) don't spawn concurrent workers.
  bool _pumping = false;
  bool _disposed = false;

  /// Tasks currently being executed in this process, so a re-pump doesn't pick
  /// up a task that's mid-run (its executionStatus is `running`).
  final Set<int> _active = {};

  /// Per-task worker attempt counts, to cap retries on a task that keeps
  /// failing to submit rather than spinning forever.
  final Map<int, int> _attempts = {};

  static const int _maxAttemptsPerTask = 2;
  static const int _maxTurnsPerTask = 12;
  static const int _maxTurnsPerStage = 8;
  static const Duration _tickInterval = Duration(seconds: 30);
  static const Duration _buildPollInterval = Duration(seconds: 3);
  static const Duration _buildTimeout = Duration(minutes: 30);

  ProjectOrchestrator(this.ref, this.projectId);

  NexusDatabase get _db => ref.read(nexusDatabaseProvider);

  void start() {
    _projectSub = _db.watchProject(projectId).listen((project) {
      if (project?.orchestrationState == 'running') {
        unawaited(_pump());
      }
    });
    _ticker = Timer.periodic(_tickInterval, (_) => unawaited(_pump()));
  }

  void dispose() {
    _disposed = true;
    _projectSub?.cancel();
    _ticker?.cancel();
  }

  /// Walk the pipeline one unit of work at a time — implement, then verify, then
  /// build, then merge — until the project is no longer running, falls outside
  /// working hours, or there's nothing left to do.
  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    try {
      while (!_disposed) {
        final project = await _db.getProjectById(projectId);
        if (project == null || project.orchestrationState != 'running') break;
        if (!isWithinWorkingHours(project)) break;

        final (task, stage) = await _nextPipelineWork();
        if (task == null || stage == null) break;

        _active.add(task.task_pk);
        try {
          switch (stage) {
            case _Stage.implement:
              await _runTaskToSubmission(task);
            case _Stage.verify:
              await _runVerifyStage(task);
            case _Stage.build:
              await _runBuildStage(task);
            case _Stage.merge:
              await _runMergeStage(task);
          }
        } catch (e, st) {
          debugPrint('[Orchestrator p$projectId] task ${task.task_pk} ${stage.name} errored: $e\n$st');
        } finally {
          _active.remove(task.task_pk);
        }
      }
    } finally {
      _pumping = false;
    }
  }

  /// Pick the single next task + stage to act on, in pipeline order. Implement
  /// work has priority (keeps the board moving), then verify, build, and merge
  /// for tasks already in flight.
  Future<(Task?, _Stage?)> _nextPipelineWork() async {
    final implement = await _nextAssignableTask();
    if (implement != null) return (implement, _Stage.implement);

    final tasks = await _db.getTasksForProject(projectId);
    Task? firstWhere(bool Function(Task) test) {
      final matches = tasks.where((t) => !_active.contains(t.task_pk) && test(t)).toList();
      if (matches.isEmpty) return null;
      matches.sort((a, b) {
        final p = _priorityRank(b.priority).compareTo(_priorityRank(a.priority));
        if (p != 0) return p;
        return a.createdAt.compareTo(b.createdAt);
      });
      return matches.first;
    }

    final verify = firstWhere((t) =>
        t.status == TaskStatus.review && t.executionStatus == TaskExecStatus.submitted);
    if (verify != null) return (verify, _Stage.verify);

    final build = firstWhere((t) =>
        t.status == TaskStatus.review &&
        t.executionStatus == TaskExecStatus.verified &&
        t.requiresBuild);
    if (build != null) return (build, _Stage.build);

    final merge = firstWhere((t) =>
        t.status == TaskStatus.review &&
        (t.executionStatus == TaskExecStatus.built ||
            (t.executionStatus == TaskExecStatus.verified && !t.requiresBuild)));
    if (merge != null) return (merge, _Stage.merge);

    return (null, null);
  }

  /// The next task ready for a worker: assigned to a worker-role persona, on the
  /// Todo board, not already running here, and under its retry cap. Highest
  /// priority first, then oldest.
  Future<Task?> _nextAssignableTask() async {
    final tasks = await _db.getTasksForProject(projectId);
    final candidates = <Task>[];
    for (final t in tasks) {
      if (t.task_agent_fk == null) continue;
      if (_active.contains(t.task_pk)) continue;
      if ((_attempts[t.task_pk] ?? 0) >= _maxAttemptsPerTask) continue;
      final isStartable = t.status == TaskStatus.todo &&
          (t.executionStatus == TaskExecStatus.idle ||
              t.executionStatus == TaskExecStatus.queued ||
              t.executionStatus == TaskExecStatus.failed);
      if (!isStartable) continue;
      candidates.add(t);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final p = _priorityRank(b.priority).compareTo(_priorityRank(a.priority));
      if (p != 0) return p;
      return a.createdAt.compareTo(b.createdAt);
    });
    return candidates.first;
  }

  int _priorityRank(String p) => switch (p.toUpperCase()) {
        'HIGH' || 'HI' || 'URGENT' => 3,
        'MED' || 'MEDIUM' => 2,
        'LOW' => 1,
        _ => 2,
      };

  /// Spawn an ephemeral worker for [task] and run it until it submits (or the
  /// turn cap is hit, or the project leaves the running state).
  Future<void> _runTaskToSubmission(Task task) async {
    final agentFk = task.task_agent_fk;
    if (agentFk == null) return;

    final persona = await _db.resolveAgentPersona(agentFk);
    if (persona == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: assigned persona $agentFk not found.');
      return;
    }
    final role = agentRoleFromKey(persona.title);
    if (role == null || !role.isWorker) {
      // Only worker roles are auto-spawned; coordinator/verifier/PM tasks are
      // driven elsewhere. Leave the task untouched.
      return;
    }

    final resolved = await _resolveBackend(persona);
    if (resolved == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: no inference server for persona ${persona.name}.');
      return;
    }

    final branch = 'task/${task.task_pk}';

    // Workspace / git / build access for the worker's file & build tools.
    final handles = await _resolveWorkspaceHandles();
    final workspace = handles.ws;
    final git = handles.git;
    final buildService = handles.build;

    // Subtasks branch off their parent's branch so their commits merge back
    // into the parent (not the trunk); top-level tasks branch off main.
    final base = await _integrationTargetBranch(task);
    // Put the worktree on the task branch (created off [base]) so commits land
    // on task/<id>.
    await _checkout(git, branch, task.task_pk, base: base);

    final prompts = await _loadPrompts();
    final vars = _varsFor(task, branch, targetBranch: base);

    // One conversation PER AGENT: reuse this worker's dedicated session so all
    // of its tasks land in a single ongoing thread (the person can follow the
    // agent there) instead of a brand-new session on every task update.
    final workerSessionPk =
        await _db.getOrCreateAgentChatSession(projectId, agentFk, persona.name);
    _attempts[task.task_pk] = (_attempts[task.task_pk] ?? 0) + 1;
    await _db.markTaskRunning(task.task_pk, workerSessionPk: workerSessionPk, workBranch: branch);

    final session = ProjectCoordinatorSession(
      client: resolved.client,
      projectId: projectId,
      projectName: persona.name,
      db: _db,
      model: resolved.model,
      chatSessionPk: workerSessionPk,
      permissions: AgentToolPermissions.fromConfigJson(persona.configJson),
      // Autonomous: there's no human to approve `ask` tools, so auto-approve.
      // The dangerous ops (push/merge) are *denied* for worker roles by the
      // rule engine, so this can't escalate a worker beyond its branch.
      confirmAsk: (_, _) async => true,
      agentName: persona.name,
      workspace: workspace,
      git: git,
      buildService: buildService,
      // Autonomous coders need file/git/build tools directly — no progressive
      // disclosure (that's for the interactive PM chat).
      leanTools: false,
      systemPromptOverride:
          '${defaultSystemPrompt(role)}\n${prompts.render(OrchestratorPromptField.workerFraming, vars)}',
      enableThinking: resolveEnableThinking(
        agent: personaThinkingMode(persona.configJson, personaName: persona.name),
        task: ThinkingMode.fromString(task.thinkingMode),
      ),
    );

    var kickoff = prompts.render(OrchestratorPromptField.workerKickoff, vars);
    for (var turn = 0; turn < _maxTurnsPerTask && !_disposed; turn++) {
      // Stop promptly if the human paused/stopped the project mid-task.
      final project = await _db.getProjectById(projectId);
      if (project == null || project.orchestrationState != 'running') {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: project not running, halting worker.');
        return;
      }

      try {
        await for (final _ in session.runTurn(kickoff)) {
          // Drain the stream; tool effects are applied inside runTurn.
        }
      } catch (e) {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: turn $turn failed: $e');
        return;
      }

      final fresh = await _db.getTaskById(task.task_pk);
      if (fresh == null) return;
      if (fresh.executionStatus == TaskExecStatus.submitted) {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: submitted for review.');
        return;
      }

      kickoff = prompts.render(OrchestratorPromptField.workerContinue, vars);
    }
    debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: hit turn cap without submission.');
  }

  /// Load this project's effective orchestrator prompt templates (per-project
  /// overrides merged over the built-in defaults).
  Future<OrchestratorPrompts> _loadPrompts() async {
    final project = await _db.getProjectById(projectId);
    return OrchestratorPrompts.fromJson(project?.orchestratorPromptsJson);
  }

  /// The placeholder values for [task]'s prompt templates.
  PromptVars _varsFor(Task task, String branch, {String targetBranch = 'main'}) =>
      PromptVars(
        taskId: task.task_pk,
        title: task.title,
        branch: branch,
        targetBranch: targetBranch,
        description: task.description ?? '',
        acceptanceCriteria: task.acceptanceCriteria ?? '',
        verification: task.verification ?? '',
      );

  /// The branch [task] integrates into: the parent task's work branch when it is
  /// a subtask, otherwise the trunk ("main"). Falls back to "main" if the parent
  /// is missing.
  Future<String> _integrationTargetBranch(Task task) async {
    final parentPk = task.task_parent_fk;
    if (parentPk == null) return 'main';
    final parent = await _db.getTaskById(parentPk);
    if (parent == null) return 'main';
    final pb = parent.workBranch?.trim();
    return (pb != null && pb.isNotEmpty) ? pb : 'task/$parentPk';
  }

  // ── Verify stage ──────────────────────────────────────────────────────

  /// Spawn an ephemeral Verification Agent for a submitted [task]. It runs the
  /// task's verification and emits a verdict (run_verification → submit_verdict),
  /// which advances the task to `verified` (awaiting build/merge) or back to the
  /// board on failure. If no Verification Agent persona exists, the task is left
  /// submitted for a human to verify.
  Future<void> _runVerifyStage(Task task) async {
    final persona = await _findPersonaForRole(AgentRole.verificationAgent);
    if (persona == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: no Verification Agent persona; leaving submitted.');
      return;
    }
    final resolved = await _resolveBackend(persona);
    if (resolved == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: no inference server for verifier ${persona.name}.');
      return;
    }
    final handles = await _resolveWorkspaceHandles();
    final branch = task.workBranch ?? 'task/${task.task_pk}';
    await _checkout(handles.git, branch, task.task_pk);

    final prompts = await _loadPrompts();
    final vars = _varsFor(task, branch);
    // Reuse the Verification Agent's single per-agent session (see worker stage).
    final sessionPk =
        await _db.getOrCreateAgentChatSession(projectId, persona.agent_pk, persona.name);

    final session = ProjectCoordinatorSession(
      client: resolved.client,
      projectId: projectId,
      projectName: persona.name,
      db: _db,
      model: resolved.model,
      chatSessionPk: sessionPk,
      permissions: AgentToolPermissions.fromConfigJson(persona.configJson),
      confirmAsk: (_, _) async => true,
      agentName: persona.name,
      workspace: handles.ws,
      git: handles.git,
      buildService: handles.build,
      // Autonomous coders need file/git/build tools directly — no progressive
      // disclosure (that's for the interactive PM chat).
      leanTools: false,
      systemPromptOverride:
          '${defaultSystemPrompt(AgentRole.verificationAgent)}\n${prompts.render(OrchestratorPromptField.verifyFraming, vars)}',
      enableThinking: resolveEnableThinking(
        agent: personaThinkingMode(persona.configJson, personaName: persona.name),
        task: ThinkingMode.fromString(task.thinkingMode),
      ),
    );

    var kickoff = prompts.render(OrchestratorPromptField.verifyKickoff, vars);
    for (var turn = 0; turn < _maxTurnsPerStage && !_disposed; turn++) {
      if (!await _stillRunning()) return;
      try {
        await for (final _ in session.runTurn(kickoff)) {}
      } catch (e) {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: verify turn $turn failed: $e');
        return;
      }
      final fresh = await _db.getTaskById(task.task_pk);
      if (fresh == null) return;
      if (fresh.executionStatus != TaskExecStatus.submitted &&
          fresh.executionStatus != TaskExecStatus.verifying) {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: verdict recorded (${fresh.executionStatus}).');
        return;
      }
      kickoff = prompts.render(OrchestratorPromptField.verifyContinue, vars);
    }
    debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: verify hit turn cap without a verdict.');
  }

  // ── Build stage ───────────────────────────────────────────────────────

  /// Drive the build gate for a `verified` task that `requiresBuild`, with no
  /// LLM in the loop: start the configured workflow or Docker build, wait for it
  /// to finish, and advance the task to `built` (awaiting merge) or back to the
  /// board on failure. The run is started with `taskPk: null` so BuildService's
  /// auto-approve-on-green rule doesn't fire — this stage owns the outcome.
  Future<void> _runBuildStage(Task task) async {
    final project = await _db.getProjectById(projectId);
    if (project == null) return;
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final build = handles.build;
    if (ws == null || build == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: workspace/build unavailable; cannot build.');
      return;
    }
    final branch = task.workBranch ?? 'task/${task.task_pk}';
    final workflowPath = task.workflowPath?.trim();
    final dockerfilePath = task.dockerfilePath?.trim();
    if ((workflowPath == null || workflowPath.isEmpty) &&
        (dockerfilePath == null || dockerfilePath.isEmpty)) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: requiresBuild but no workflow/dockerfile path; treating gate as satisfied.');
      await _db.recordTaskBuildOutcome(task.task_pk, passed: true);
      return;
    }

    await _db.beginTaskBuild(task.task_pk);
    int runPk;
    try {
      if (workflowPath != null && workflowPath.isNotEmpty) {
        final started = await build.startWorkflowRun(
          clientPk: project.client_fk,
          projectPk: projectId,
          ws: ws,
          workflowPath: workflowPath,
          branch: branch,
          triggeredBy: 'orchestrator',
        );
        runPk = started.runPk;
      } else {
        final imageTag = (task.imageTag?.trim().isNotEmpty ?? false)
            ? task.imageTag!.trim()
            : 'task-${task.task_pk}:latest';
        final started = await build.startDockerBuild(
          clientPk: project.client_fk,
          projectPk: projectId,
          ws: ws,
          dockerfilePath: dockerfilePath!,
          imageTag: imageTag,
          branch: branch,
          triggeredBy: 'orchestrator',
        );
        runPk = started.runPk;
      }
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: build failed to start: $e');
      await _db.recordTaskBuildOutcome(task.task_pk, passed: false);
      return;
    }

    final deadline = DateTime.now().add(_buildTimeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_buildPollInterval);
      final run = await _db.getCiRun(runPk);
      if (run == null) break;
      final status = CiStatusX.fromWire(run.status);
      if (status.isTerminal) {
        final passed = status == CiStatus.success;
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: build run $runPk → ${status.wire}.');
        await _db.recordTaskBuildOutcome(task.task_pk, passed: passed);
        return;
      }
    }
    debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: build run $runPk did not finish in time; failing the gate.');
    await _db.recordTaskBuildOutcome(task.task_pk, passed: false);
  }

  // ── Merge stage ───────────────────────────────────────────────────────

  /// Spawn an ephemeral Coordinator to integrate a merge-ready [task]: merge
  /// `task/<id>` into its target branch (the parent task's branch for a subtask,
  /// otherwise main) and approve the task to Done. The Coordinator is the only
  /// role allowed to merge. If no Coordinator persona exists, the task is left
  /// awaiting a human merge.
  Future<void> _runMergeStage(Task task) async {
    final persona = await _findPersonaForRole(AgentRole.coordinator);
    if (persona == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: no Coordinator persona; leaving for human merge.');
      return;
    }
    final resolved = await _resolveBackend(persona);
    if (resolved == null) {
      debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: no inference server for coordinator ${persona.name}.');
      return;
    }
    final handles = await _resolveWorkspaceHandles();
    // A subtask integrates into its parent's branch; a top-level task into main.
    // Put the worktree on that target before the Coordinator merges into it.
    final targetBranch = await _integrationTargetBranch(task);
    await _checkout(handles.git, targetBranch, task.task_pk);

    final branch = task.workBranch ?? 'task/${task.task_pk}';
    final prompts = await _loadPrompts();
    final vars = _varsFor(task, branch, targetBranch: targetBranch);
    await _db.beginTaskMerge(task.task_pk);

    // Reuse the Coordinator's single per-agent session (see worker stage).
    final sessionPk =
        await _db.getOrCreateAgentChatSession(projectId, persona.agent_pk, persona.name);

    final session = ProjectCoordinatorSession(
      client: resolved.client,
      projectId: projectId,
      projectName: persona.name,
      db: _db,
      model: resolved.model,
      chatSessionPk: sessionPk,
      permissions: AgentToolPermissions.fromConfigJson(persona.configJson),
      confirmAsk: (_, _) async => true,
      agentName: persona.name,
      workspace: handles.ws,
      git: handles.git,
      buildService: handles.build,
      // Autonomous coders need file/git/build tools directly — no progressive
      // disclosure (that's for the interactive PM chat).
      leanTools: false,
      systemPromptOverride:
          '${defaultSystemPrompt(AgentRole.coordinator)}\n${prompts.render(OrchestratorPromptField.mergeFraming, vars)}',
      enableThinking: resolveEnableThinking(
        agent: personaThinkingMode(persona.configJson, personaName: persona.name),
        task: ThinkingMode.fromString(task.thinkingMode),
      ),
    );

    var kickoff = prompts.render(OrchestratorPromptField.mergeKickoff, vars);
    for (var turn = 0; turn < _maxTurnsPerStage && !_disposed; turn++) {
      if (!await _stillRunning()) return;
      try {
        await for (final _ in session.runTurn(kickoff)) {}
      } catch (e) {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: merge turn $turn failed: $e');
        return;
      }
      final fresh = await _db.getTaskById(task.task_pk);
      if (fresh == null) return;
      if (fresh.executionStatus == TaskExecStatus.done ||
          fresh.status == TaskStatus.todo) {
        debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: merge stage resolved (${fresh.executionStatus}).');
        return;
      }
      kickoff = prompts.render(OrchestratorPromptField.mergeContinue, vars);
    }
    debugPrint('[Orchestrator p$projectId] task ${task.task_pk}: merge hit turn cap without resolution.');
  }

  // ── Shared helpers ──────────────────────────────────────────────────────

  /// First persona for the client whose stored title maps to [role], or null.
  Future<AgentPersona?> _findPersonaForRole(AgentRole role) async {
    final project = await _db.getProjectById(projectId);
    if (project == null) return null;
    final personas = await _db.getAgentPersonasForClient(project.client_fk);
    for (final p in personas) {
      if (agentRoleFromKey(p.title) == role) return p;
    }
    return null;
  }

  /// Resolve the workspace, git engine, and build service for this project.
  /// Any of them may be null if the workspace is unavailable.
  Future<({Workspace? ws, NxtprjGitEngine? git, BuildService? build})> _resolveWorkspaceHandles() async {
    Workspace? ws;
    NxtprjGitEngine? git;
    BuildService? build;
    try {
      ws = await ref.read(workspaceFsProvider(projectId).future);
      git = await ref.read(gitEngineProvider(projectId).future);
      build = ref.read(buildServiceProvider);
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] workspace unavailable: $e');
    }
    return (ws: ws, git: git, build: build);
  }

  /// Put the worktree on [branch], creating it if needed. When the branch must
  /// be created and [base] is given (and exists), the worktree is first switched
  /// to [base] so the new branch diverges from it — this is how a subtask branch
  /// is rooted on its parent's branch. No-op when git is null.
  Future<void> _checkout(NxtprjGitEngine? git, String branch, int taskPk,
      {String? base}) async {
    if (git == null) return;
    try {
      final existing = await git.branches();
      if (existing.contains(branch)) {
        await git.checkoutBranch(branch);
        return;
      }
      // New branch: root it on [base] (parent branch / main) when available.
      if (base != null && base != branch && existing.contains(base)) {
        await git.checkoutBranch(base);
      }
      await git.createBranch(branch, checkout: true);
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] task $taskPk: checkout "$branch" failed: $e');
    }
  }

  /// True while the project is still in the running state — used to bail out of
  /// a multi-turn agent stage promptly when the human pauses/stops.
  Future<bool> _stillRunning() async {
    final project = await _db.getProjectById(projectId);
    return project != null && project.orchestrationState == 'running';
  }

  /// Resolve the inference backend + chat model for [persona] from its connected
  /// server (or the client's first server). Returns null when none exist.
  Future<({InferenceBackend client, String? model})?> _resolveBackend(AgentPersona persona) async {
    final project = await _db.getProjectById(projectId);
    if (project == null) return null;
    final servers = await _db.getInferenceServersForClient(project.client_fk);
    if (servers.isEmpty) return null;

    // Default to the Nexus Router (subscription) server when present (signed in),
    // else the first configured server. An explicit agent provider_fk wins.
    var chosen = servers.firstWhere(
      (s) => isRoutedProviderType(s.providerType),
      orElse: () => servers.first,
    );
    if (persona.provider_fk != null) {
      for (final s in servers) {
        if (s.server_pk == persona.provider_fk) {
          chosen = s;
          break;
        }
      }
    }

    final models = (jsonDecode(chosen.availableModelsJson) as List).cast<String>();

    final personaModel = persona.llmModel?.trim();
    final model = (personaModel != null && personaModel.isNotEmpty)
        ? personaModel
        : ((chosen.selectedModel != null && chosen.selectedModel!.trim().isNotEmpty)
            ? chosen.selectedModel!.trim()
            : (models.isNotEmpty ? models.first : null));

    final uiServer = ui_server.InferenceServer(
      id: chosen.server_pk.toString(),
      name: chosen.name,
      baseUrl: chosen.baseUrl,
      apiKey: chosen.apiKey,
      providerType: 'lemonade',
      selectedModel: chosen.selectedModel,
      availableModels: models,
    );
    return (client: backendForServer(uiServer, agentName: persona.name), model: model);
  }
}

/// The pipeline stage a task is ready for, in execution order.
enum _Stage { implement, verify, build, merge }

/// One [ProjectOrchestrator] per project. Kept alive while anything (e.g. the
/// project workspace view) watches it; it self-starts on creation.
final projectOrchestratorProvider = Provider.family<ProjectOrchestrator, int>((ref, projectId) {
  final orchestrator = ProjectOrchestrator(ref, projectId)..start();
  ref.onDispose(orchestrator.dispose);
  return orchestrator;
});
