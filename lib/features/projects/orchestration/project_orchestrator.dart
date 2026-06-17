// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/core/providers/worker_capture_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/inference/inference_backend_factory.dart'
    show backendForServer;
import 'package:nexus_projects_client/infrastructure/inference/routed_server.dart'
    show isRoutedProviderType;
import 'package:nexus_projects_client/infrastructure/inference/inference_client.dart'
    show InferenceBackend;
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_server;
import 'package:nexus_projects_client/infrastructure/lemonade/api/types/model_info.dart'
    show ApiModelInfo;
import 'package:nexus_projects_client/infrastructure/lemonade/services/persona_model_resolver.dart'
    show resolveAgentChatModel, defaultOmniCollectionForTitle;
import 'package:nexus_projects_client/infrastructure/lemonade/api/exceptions.dart'
    show LemonadeApiException;
import 'package:nexus_projects_client/features/ai_providers/providers/ai_servers_cache_provider.dart'
    show aiServersCacheProvider;
import 'package:nexus_projects_client/infrastructure/workspace/async_lock.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/git_engine_provider.dart';
import 'package:nexus_projects_client/infrastructure/build/build_models.dart'
    show CiStatus, CiStatusX;
import 'package:nexus_projects_client/infrastructure/build/build_service.dart';
import 'package:nexus_projects_client/infrastructure/build/build_service_provider.dart';
import 'package:nexus_projects_client/features/agents/thinking_mode.dart';
import 'package:nexus_projects_client/features/agents/agent_role.dart';
import 'package:nexus_projects_client/features/agents/agent_role_policy.dart';
import 'package:nexus_projects_client/features/agents/agent_tool_permissions.dart';
import 'package:nexus_projects_client/features/projects/coordinator_session.dart';
import 'package:nexus_projects_client/features/projects/orchestration/orchestrator_prompts.dart';
import 'package:nexus_projects_client/features/projects/orchestration/milestone_planner.dart';
import 'package:nexus_projects_client/features/projects/project_baseline.dart'
    show buildProjectBaseline;
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

  /// True while the one-shot Templater (base-project scaffold) is running this
  /// session, so repeated pumps don't launch a second scaffolder concurrently.
  bool _templating = false;

  /// Tasks currently being executed in this process, so a re-pump doesn't pick
  /// up a task that's mid-run (its executionStatus is `running`).
  final Set<int> _active = {};

  /// Per-task worker attempt counts, to cap retries on a task that keeps
  /// failing to submit rather than spinning forever.
  final Map<int, int> _attempts = {};

  /// File-claim table for the same-file queue: normalized workspace path → the
  /// task_pk that currently OWNS it. A worker claims a file the first time it
  /// edits it and holds it until the task merges, so two tasks never submit
  /// conflicting changes to the same file in parallel; a second task that needs
  /// the file is parked and retried. Reset whenever the orchestrator is disposed
  /// (project swap / app close), and swept every pump so a lock is never held by
  /// a task that isn't actively running or awaiting integration (no indefinite
  /// hogging — the exact failure mode we hit with agent slots).
  final Map<String, int> _fileOwners = {};

  /// Release every file lock held by [taskPk].
  void _releaseLocks(int taskPk) =>
      _fileOwners.removeWhere((_, owner) => owner == taskPk);

  /// Normalize a workspace path for lock identity (case-insensitive FS, ignore a
  /// leading slash) so "/Assets/X.cs" and "assets/x.cs" are the same lock.
  static String _normFile(String path) {
    var p = path.trim().replaceAll('\\', '/').toLowerCase();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p;
  }

  /// After hitting the plan's concurrent-connection cap (HTTP 429), pause NEW
  /// agent dispatch until this time so we stop piling past the cap — in-flight
  /// stages keep running, and the task that 429'd goes back to the board (it is
  /// NOT counted as a failure or Blocked; it's pure backpressure).
  DateTime? _connBackoffUntil;

  // Per-task retry budget within ONE run before a task is surfaced as Blocked.
  // Kept generous so a couple of transient hiccups (a flaky worker turn, a
  // momentary backend blip) don't strand otherwise-workable tasks — blocking is
  // a "needs a human look" signal, not a hair-trigger. (Re)starting the loop
  // clears this and requeues blocked tasks, so it's never a permanent dead end.
  static const int _maxAttemptsPerTask = 5;

  /// Connections kept free for the interactive Coordinator (the story-maker you
  /// talk to during/after setup to add & adjust user stories). Without this, a
  /// burst of worker agents (e.g. the generalist) can claim every connection the
  /// plan allows, starving the Coordinator so you can't edit stories while work
  /// is running. We hold this many slots back from the worker pool — but never so
  /// many that no worker can run (a 1-connection plan still does work, just
  /// shared with the Coordinator).
  static const int _reservedCoordinatorSlots = 1;

  static const int _maxTurnsPerTask = 12;
  static const int _maxTurnsPerStage = 8;
  static const Duration _connBackoff = Duration(seconds: 20);
  static const Duration _tickInterval = Duration(seconds: 30);
  static const Duration _buildPollInterval = Duration(seconds: 3);
  static const Duration _buildTimeout = Duration(minutes: 30);

  /// Lines from a CI log worth handing the worker on a red gate: analyzer/
  /// compiler diagnostics (`error -`, `warning -`, `info -`), `file.dart:line`
  /// references, the analyze summary, and test/exception failures.
  static final RegExp _diagLineRe = RegExp(
    r'(\b(error|warning|info)\b\s*[-:]|\.dart:\d+|\bissues? found\b|\bError:|\bFAILED\b|\bException\b)',
    caseSensitive: false,
  );

  ProjectOrchestrator(this.ref, this.projectId);

  NexusDatabase get _db => ref.read(nexusDatabaseProvider);

  void start() {
    // Clear any leftover per-task working-tree disks from a previous crash.
    unawaited(pruneTaskDisks(projectId));
    // A new run starts every task with a clean retry budget, and any task that
    // was Blocked in a previous run gets another chance — so pressing Start
    // always actually starts the work instead of immediately re-surfacing a
    // board full of Blocked tasks the user can't get past.
    _attempts.clear();
    unawaited(_db.requeueBlockedTasks(projectId));
    // Reconcile tasks orphaned mid-run by a crash/quit: our in-memory _active
    // set is empty on a fresh start, so any task still marked `running` in the
    // DB would never be re-picked. Return them to the board.
    unawaited(_reconcileOrphans());
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
    // Drop all file claims so a fresh orchestrator (e.g. after a project swap)
    // never inherits a stale lock — the anti-hog reset.
    _fileOwners.clear();
  }

  /// Fill up to N agent slots (N = the account's max concurrency) with the next
  /// fair, backlog-weighted pieces of work, launching each on its own isolated
  /// working tree. Returns immediately after dispatching; each stage frees its
  /// slot and re-pumps on completion. [_pumping] guards only the dispatch loop,
  /// not the work, so it never serializes the agents.
  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    try {
      final project = await _db.getProjectById(projectId);
      if (project == null || project.orchestrationState != 'running') return;
      if (!isWithinWorkingHours(project)) return;

      // Honour the connection-cap backoff: a recent 429 means every slot the plan
      // allows is in use (often by the interactive Coordinator chat too), so don't
      // launch MORE agents — let in-flight work finish and free a connection.
      if (_connBackoffUntil != null &&
          DateTime.now().isBefore(_connBackoffUntil!)) {
        return;
      }

      // Templater gate: before any worker runs, the base project must be
      // scaffolded ONCE (committed to main). Until then no task work dispatches,
      // so the agents don't all race to create the project from an empty main.
      if (!await _ensureTemplated(project)) return;

      final cap = await _concurrencyCap(project);
      // Hold a connection back for the interactive Coordinator so worker agents
      // can't claim every slot and starve story editing. Never drop below 1, so
      // a single-connection plan still makes progress.
      final workerCap = (cap - _reservedCoordinatorSlots).clamp(1, cap);
      while (!_disposed && _active.length < workerCap) {
        final (task, stage) = await _nextPipelineWork();
        if (task == null || stage == null) break;
        _active.add(task.task_pk);
        unawaited(_runStage(task, stage));
      }
      await _surfaceStalledTasks();
      await _maybeAdvanceMilestone(project);
    } finally {
      _pumping = false;
    }
  }

  /// Return tasks left `running` by a prior crash/quit (not tracked in [_active])
  /// to the board so they get re-picked. Safe to call repeatedly.
  Future<void> _reconcileOrphans() async {
    try {
      final tasks = await _db.getTasksForProject(projectId);
      for (final t in tasks) {
        if (t.executionStatus == TaskExecStatus.running &&
            !_active.contains(t.task_pk)) {
          await _db.markTaskYieldedBack(t.task_pk);
        }
      }
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] orphan reconcile failed: $e');
    }
  }

  /// Surface tasks that have exhausted their retry budget: move them to the
  /// Blocked column so they're visible to the user instead of silently sitting
  /// on Todo and being skipped every pump. Idempotent — a Blocked task is no
  /// longer on Todo, so it isn't re-evaluated here.
  Future<void> _surfaceStalledTasks() async {
    try {
      final tasks = await _db.getTasksForProject(projectId);
      for (final t in tasks) {
        // Block any task that has burned its retry budget and isn't actively
        // being worked — whether it's stalled on Todo (never started) OR stuck
        // in Review (a verify/merge that never resolves). The latter is what
        // left tasks frozen in Review holding a slot; now they go Blocked (red)
        // so they're visible and stop consuming the connection pool.
        final stalled =
            t.status == TaskStatus.todo || t.status == TaskStatus.review;
        if ((_attempts[t.task_pk] ?? 0) >= _maxAttemptsPerTask &&
            stalled &&
            !_active.contains(t.task_pk)) {
          debugPrint(
            '[Orchestrator p$projectId] task ${t.task_pk} (${t.status}/'
            '${t.executionStatus}) exhausted $_maxAttemptsPerTask attempts → '
            'Blocked.',
          );
          await _db.markTaskBlocked(t.task_pk);
          // Wipe the in-memory retry count so a human who later moves this task
          // Blocked → Todo gets a FRESH budget. Without this the stale count
          // (already ≥ cap) makes it re-block on the very next pump without ever
          // running again.
          _attempts.remove(t.task_pk);
        }
      }

      // File-claim safety sweep (the anti-hog guarantee): a file may only stay
      // locked by a task that is either actively running a stage (in _active) or
      // sitting in Review awaiting integration (submitted → … → merging). Any
      // other owner — Done, Blocked, or a task that fell back to the Todo board —
      // has its claims dropped here, so no lock can be held indefinitely even if
      // an explicit release was somehow missed.
      if (_fileOwners.isNotEmpty) {
        final holding = <int>{..._active};
        for (final t in tasks) {
          if (t.status == TaskStatus.review) holding.add(t.task_pk);
        }
        _fileOwners.removeWhere((_, owner) => !holding.contains(owner));
      }
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] stall surface failed: $e');
    }
  }

  /// Run one (task, stage) to completion, then free its slot and re-pump so a
  /// waiting piece of work fills the freed slot.
  Future<void> _runStage(Task task, _Stage stage) async {
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
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk} ${stage.name} errored: $e\n$st',
      );
    } finally {
      _active.remove(task.task_pk);
      if (!_disposed) unawaited(_pump());
    }
  }

  /// Pick the single next task + stage to act on. Work is one-at-a-time (all
  /// agents share one git working tree), but instead of strict priority we use a
  /// smooth weighted round-robin across the four stages, weighted by each
  /// stage's backlog — so verify/build/merge are never starved by a long
  /// implement queue, while busier stages ("more to do") still get
  /// proportionally more turns.
  Future<(Task?, _Stage?)> _nextPipelineWork() async {
    final tasks = await _db.getTasksForProject(projectId);
    // Only the currently-open milestone batch is assignable for fresh implement
    // work; in-flight (Review) tasks always belong to it already.
    final currentMilestone =
        (await _db.getProjectById(projectId))?.currentMilestone ?? 0;
    final review = tasks
        .where(
          (t) => !_active.contains(t.task_pk) && t.status == TaskStatus.review,
        )
        .toList();

    final pools = <_Stage, List<Task>>{};
    void addPool(_Stage s, List<Task> list) {
      if (list.isNotEmpty) pools[s] = _sortByPriority(list);
    }

    // A Review task whose retry budget is spent is NOT re-picked here — it's
    // surfaced to Blocked by _surfaceStalledTasks instead of looping forever.
    bool live(Task t) => (_attempts[t.task_pk] ?? 0) < _maxAttemptsPerTask;

    addPool(_Stage.implement, _assignableTasks(tasks, currentMilestone));
    addPool(
      _Stage.verify,
      review
          // `verifying` is included so a verify stage that was interrupted
          // (turn cap / crash / app restart) AFTER run_verification set the task
          // to `verifying` is RE-PICKED rather than stranded — that strand was
          // the "stuck in Review forever, holding a slot" bug.
          .where(
            (t) =>
                (t.executionStatus == TaskExecStatus.submitted ||
                    t.executionStatus == TaskExecStatus.verifying) &&
                live(t),
          )
          .toList(),
    );
    addPool(
      _Stage.build,
      review
          .where(
            (t) =>
                ((t.executionStatus == TaskExecStatus.verified &&
                        t.requiresBuild) ||
                    t.executionStatus == TaskExecStatus.building) &&
                live(t),
          )
          .toList(),
    );
    addPool(
      _Stage.merge,
      review
          // `merging` is included for the same reason: an interrupted merge
          // (after beginTaskMerge set `merging`) is re-driven instead of stuck.
          .where(
            (t) =>
                (t.executionStatus == TaskExecStatus.built ||
                    t.executionStatus == TaskExecStatus.merging ||
                    (t.executionStatus == TaskExecStatus.verified &&
                        !t.requiresBuild)) &&
                live(t),
          )
          .toList(),
    );

    // DRAIN-FIRST priority: always advance work that's already in flight before
    // starting anything new, so a task's file locks (held from first edit until
    // merge) are released as soon as possible instead of many tasks piling into
    // Review holding locks and starving the Todo queue behind them. Order:
    // merge → build → verify → implement. A new Todo is only picked up when
    // there's no in-flight task left to push toward Done.
    for (final stage in const [
      _Stage.merge,
      _Stage.build,
      _Stage.verify,
      _Stage.implement,
    ]) {
      final pool = pools[stage];
      if (pool != null && pool.isNotEmpty) return (pool.first, stage);
    }
    return (null, null);
  }

  List<Task> _sortByPriority(List<Task> list) {
    list.sort((a, b) {
      final p = _priorityRank(b.priority).compareTo(_priorityRank(a.priority));
      if (p != 0) return p;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Tasks ready for a worker: assigned to a worker-role persona, on the Todo
  /// board, not already running here, under the retry cap, AND within the
  /// currently-open milestone batch ([currentMilestone]). The milestone filter is
  /// what makes work proceed one batch at a time: a later milestone's tasks stay
  /// on the board until the project advances to them.
  List<Task> _assignableTasks(List<Task> tasks, int currentMilestone) {
    final out = <Task>[];
    for (final t in tasks) {
      if (t.task_agent_fk == null) continue;
      if (_active.contains(t.task_pk)) continue;
      if ((_attempts[t.task_pk] ?? 0) >= _maxAttemptsPerTask) continue;
      if ((t.milestoneOrder ?? 0) > currentMilestone) continue;
      final isStartable =
          t.status == TaskStatus.todo &&
          (t.executionStatus == TaskExecStatus.idle ||
              t.executionStatus == TaskExecStatus.queued ||
              t.executionStatus == TaskExecStatus.failed);
      if (isStartable) out.add(t);
    }
    return out;
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
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: assigned persona $agentFk not found.',
      );
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
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: no inference server for persona ${persona.name}.',
      );
      return;
    }

    final branch = 'task/${task.task_pk}';

    // This worker runs on its OWN isolated working tree so it can run in
    // parallel with other agents without clobbering their files. Git objects/
    // refs are shared; the lane serializes those writes.
    final th = await _resolveTaskHandles(task.task_pk);
    if (th == null) return;

    // Subtasks branch off their parent's branch so their commits merge back
    // into the parent (not the trunk); top-level tasks branch off main.
    final base = await _integrationTargetBranch(task);
    // Root the task branch on its base and hydrate this task's tree from it,
    // serialized through the lane (shared object/ref DB is single-isolate).
    await th.lane.run(() async {
      // RE-ROOT every (re)attempt: drop any prior branch first so a redo after a
      // merge conflict — or a task resuming after being parked for a file lock —
      // rebases onto the CURRENT target instead of its stale, diverged work.
      // This is what makes the merge-conflict "reject → worker rebases" recovery
      // actually rebase (createBranchAt alone no-ops on an existing branch).
      await th.git.deleteBranch(branch);
      await th.git.createBranchAt(branch, base: base);
      await th.git.materializeInto(branch, th.tree);
    });

    // File-claim queue: claim a file the first time this worker edits it; if
    // another task holds it, deny (the tool returns a "queued" message) and flag
    // the task to PARK. Locks are kept past submission (until merge) so no two
    // tasks submit conflicting edits to the same file; a non-submitting run
    // releases them in the finally below. Declared OUTSIDE the try so the finally
    // can read `submitted`.
    var parked = false;
    var submitted = false;
    bool claim(String path) {
      final p = _normFile(path);
      final owner = _fileOwners[p];
      if (owner == null || owner == task.task_pk) {
        _fileOwners[p] = task.task_pk;
        return true;
      }
      parked = true;
      return false;
    }

    try {
      final prompts = await _loadPrompts();
      final vars = _varsFor(task, branch, targetBranch: base);

      // One conversation PER AGENT: reuse this worker's dedicated session so all
      // of its tasks land in a single ongoing thread (the person can follow the
      // agent there) instead of a brand-new session on every task update.
      final workerSessionPk = await _db.getOrCreateAgentChatSession(
        projectId,
        agentFk,
        persona.name,
      );
      _attempts[task.task_pk] = (_attempts[task.task_pk] ?? 0) + 1;
      // Picked up & preparing the workspace — the task stays on the Todo board
      // (exec `queued`). It only flips to "In Progress" once a worker turn truly
      // begins (below), so the column never shows work nobody is doing.
      await _db.markTaskQueued(task.task_pk);

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
        workspace: th.tree,
        git: th.git,
        buildService: th.build,
        // Per-task isolation: the agent edits its own tree and git_commit
        // snapshots it onto its branch under the lane.
        workBranch: branch,
        gitLane: th.lane,
        fileClaim: claim,
        // Autonomous coders need file/git/build tools directly — no progressive
        // disclosure (that's for the interactive PM chat).
        leanTools: false,
        systemPromptOverride: await _framedPrompt(
          role,
          OrchestratorPromptField.workerFraming,
          prompts,
          vars,
        ),
        enableThinking: resolveEnableThinking(
          agent: personaThinkingMode(
            persona.configJson,
            personaName: persona.name,
          ),
          task: ThinkingMode.fromString(task.thinkingMode),
        ),
      );

      var kickoff = prompts.render(OrchestratorPromptField.workerKickoff, vars);
      // Diagnostics carried across turns: did the model ever actually use a tool,
      // and did the backend ever drop tools (model can't tool-call)? A worker
      // that "hits turn cap without submission" on every task is almost always
      // one of these — surface it instead of failing silently.
      var sawToolActivity = false;
      var toolsRejected = false;
      for (var turn = 0; turn < _maxTurnsPerTask && !_disposed; turn++) {
        // Stop promptly if the human paused/stopped the project mid-task — return
        // the task to the board instead of leaving it parked "In Progress".
        final project = await _db.getProjectById(projectId);
        if (project == null || project.orchestrationState != 'running') {
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: project not running, halting worker.',
          );
          await _db.markTaskYieldedBack(task.task_pk);
          return;
        }

        // The task becomes "In Progress" exactly when its agent starts a turn.
        if (turn == 0) {
          await _db.markTaskRunning(
            task.task_pk,
            workerSessionPk: workerSessionPk,
            workBranch: branch,
          );
        }

        try {
          await for (final _ in session.runTurn(
            kickoff,
            // Coders need to read → edit → commit → submit; 4 rounds often isn't
            // enough to finish in one turn, so give the worker more room before
            // the turn's forced no-tools wrap-up (which can't submit).
            maxToolRounds: 8,
            // Persist the worker's full trace (tool calls + args + results) per
            // task so it can be exported from Account → Export Tracking — but
            // ONLY when the user has toggled worker capture on (it's a lot of
            // data). Gated before the expensive jsonEncode so OFF costs nothing.
            onTrace: (messages) {
              if (!ref.read(workerCaptureProvider)) return;
              unawaited(
                _db.upsertTrainingTrace(
                  projectPk: projectId,
                  aiKind: 'worker',
                  conversationId: 'worker:$projectId:${task.task_pk}',
                  messagesJson: jsonEncode(messages),
                ),
              );
            },
            onToolResult: (r) {
              sawToolActivity = true;
              // The session emits this exact note when the backend rejected
              // tool-calling and re-ran the round WITHOUT tools — a worker can
              // never submit in that state.
              if (r.contains('rejected tool-calling')) toolsRejected = true;
              debugPrint(
                '[Orchestrator p$projectId] task ${task.task_pk} turn $turn '
                'tool → ${r.length > 140 ? '${r.substring(0, 140)}…' : r}',
              );
            },
          )) {
            // Drain the stream; tool effects are applied inside runTurn.
          }
        } catch (e) {
          if (_isNotTaskFault(e)) {
            // 429 backpressure or a transient 5xx — NOT a failure. Undo this
            // attempt so a busy/flaky gateway can never push the task to Blocked.
            // It returns to the board and is retried once things recover.
            _undoAttempt(task.task_pk);
          } else {
            debugPrint(
              '[Orchestrator p$projectId] task ${task.task_pk}: turn $turn failed: $e',
            );
          }
          await _db.markTaskYieldedBack(task.task_pk);
          return;
        }

        final fresh = await _db.getTaskById(task.task_pk);
        if (fresh == null) return;
        if (fresh.executionStatus == TaskExecStatus.submitted) {
          // KEEP this task's file locks — they're held through the merge so no
          // other task can submit conflicting edits to the same files meanwhile.
          submitted = true;
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: submitted for review.',
          );
          return;
        }

        // Parked: the worker needs a file another task holds. Don't burn an
        // attempt (it's waiting, not failing) — yield back and retry later; the
        // finally releases this task's own locks so it can't block others while
        // it waits, and the re-root on its next attempt rebuilds against current
        // main once the holder has merged.
        if (parked) {
          _undoAttempt(task.task_pk);
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: parked — a file it '
            'needs is held by another task; will retry after that task merges.',
          );
          await _db.markTaskYieldedBack(task.task_pk);
          return;
        }

        kickoff = prompts.render(OrchestratorPromptField.workerContinue, vars);
      }
      // Ran out of turns without submitting — back to the board (a fresh attempt
      // will re-pick it, up to the retry cap) rather than stuck "In Progress".
      // The diagnostics tell you WHY: `toolsRejected` = the model/server can't
      // tool-call (so it can never submit — the usual cause of every task
      // blocking); `!sawToolActivity` = the model only chatted and never touched
      // a tool. Both point at the worker model, not the task.
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: hit turn cap without '
        'submission (toolsRejected=$toolsRejected, usedTools=$sawToolActivity).',
      );
      await _db.markTaskYieldedBack(task.task_pk);
    } finally {
      // Unless this task SUBMITTED (and so should hold its files through merge),
      // drop its file claims now — a parked/failed/turn-capped run must not keep
      // others queued behind it.
      if (!submitted) _releaseLocks(task.task_pk);
      // Free this task's isolated working tree (the committed work lives on the
      // task branch in the shared object DB; the scratch tree is disposable).
      await _releaseTaskTree(task.task_pk);
    }
  }

  /// Load this project's effective orchestrator prompt templates (per-project
  /// overrides merged over the built-in defaults).
  Future<OrchestratorPrompts> _loadPrompts() async {
    final project = await _db.getProjectById(projectId);
    return OrchestratorPrompts.fromJson(project?.orchestratorPromptsJson);
  }

  /// A stage's system prompt with the AUTHORITATIVE project baseline prepended,
  /// so every agent (worker / verifier / merger) implements, checks, and merges
  /// strictly within the platforms + language/framework stack chosen at setup —
  /// never substituting a different technology.
  Future<String> _framedPrompt(
    AgentRole role,
    OrchestratorPromptField field,
    OrchestratorPrompts prompts,
    PromptVars vars,
  ) async {
    final baseline = await buildProjectBaseline(_db, projectId);
    return '$baseline\n\n${defaultSystemPrompt(role)}\n'
        '${prompts.render(field, vars)}';
  }

  /// The placeholder values for [task]'s prompt templates.
  PromptVars _varsFor(
    Task task,
    String branch, {
    String targetBranch = 'main',
  }) => PromptVars(
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
    // Count this Review attempt against the retry budget so a task that can
    // never get a verdict is surfaced to Blocked instead of cycling forever.
    _attempts[task.task_pk] = (_attempts[task.task_pk] ?? 0) + 1;
    final persona = await _findPersonaForRole(AgentRole.verificationAgent);
    if (persona == null) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: no Verification Agent persona; leaving submitted.',
      );
      return;
    }
    final resolved = await _resolveBackend(persona);
    if (resolved == null) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: no inference server for verifier ${persona.name}.',
      );
      return;
    }
    final branch = task.workBranch ?? 'task/${task.task_pk}';
    final th = await _resolveTaskHandles(task.task_pk);
    if (th == null) return;
    // Hydrate an isolated tree with the submitted task branch so the verifier
    // reads the work without touching any other agent's tree.
    await th.lane.run(() => th.git.materializeInto(branch, th.tree));

    try {
      final prompts = await _loadPrompts();
      final vars = _varsFor(task, branch);
      // Reuse the Verification Agent's single per-agent session (see worker).
      final sessionPk = await _db.getOrCreateAgentChatSession(
        projectId,
        persona.agent_pk,
        persona.name,
      );

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
        workspace: th.tree,
        git: th.git,
        buildService: th.build,
        leanTools: false,
        systemPromptOverride: await _framedPrompt(
          AgentRole.verificationAgent,
          OrchestratorPromptField.verifyFraming,
          prompts,
          vars,
        ),
        enableThinking: resolveEnableThinking(
          agent: personaThinkingMode(
            persona.configJson,
            personaName: persona.name,
          ),
          task: ThinkingMode.fromString(task.thinkingMode),
        ),
      );

      var kickoff = prompts.render(OrchestratorPromptField.verifyKickoff, vars);
      for (var turn = 0; turn < _maxTurnsPerStage && !_disposed; turn++) {
        if (!await _stillRunning()) return;
        try {
          await for (final _ in session.runTurn(kickoff)) {}
        } catch (e) {
          if (_isNotTaskFault(e)) {
            _undoAttempt(task.task_pk); // backpressure/transient — don't penalize
          } else {
            debugPrint(
              '[Orchestrator p$projectId] task ${task.task_pk}: verify turn $turn failed: $e',
            );
          }
          return;
        }
        final fresh = await _db.getTaskById(task.task_pk);
        if (fresh == null) return;
        if (fresh.executionStatus != TaskExecStatus.submitted &&
            fresh.executionStatus != TaskExecStatus.verifying) {
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: verdict recorded (${fresh.executionStatus}).',
          );
          return;
        }
        kickoff = prompts.render(OrchestratorPromptField.verifyContinue, vars);
      }
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: verify hit turn cap without a verdict.',
      );
    } finally {
      await _releaseTaskTree(task.task_pk);
    }
  }

  // ── Build stage ───────────────────────────────────────────────────────

  /// Drive the build gate for a `verified` task that `requiresBuild`, with no
  /// LLM in the loop: start the configured workflow or Docker build, wait for it
  /// to finish, and advance the task to `built` (awaiting merge) or back to the
  /// board on failure. The run is started with `taskPk: null` so BuildService's
  /// auto-approve-on-green rule doesn't fire — this stage owns the outcome.
  Future<void> _runBuildStage(Task task) async {
    _attempts[task.task_pk] = (_attempts[task.task_pk] ?? 0) + 1;
    final project = await _db.getProjectById(projectId);
    if (project == null) return;
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final build = handles.build;
    if (ws == null || build == null) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: workspace/build unavailable; cannot build.',
      );
      return;
    }
    final branch = task.workBranch ?? 'task/${task.task_pk}';
    final workflowPath = task.workflowPath?.trim();
    final dockerfilePath = task.dockerfilePath?.trim();
    if ((workflowPath == null || workflowPath.isEmpty) &&
        (dockerfilePath == null || dockerfilePath.isEmpty)) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: requiresBuild but no workflow/dockerfile path; treating gate as satisfied.',
      );
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
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: build failed to start: $e',
      );
      await _failBuildGate(task, reason: 'The build run failed to start: $e');
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
        debugPrint(
          '[Orchestrator p$projectId] task ${task.task_pk}: build run $runPk → ${status.wire}.',
        );
        if (passed) {
          await _db.recordTaskBuildOutcome(task.task_pk, passed: true);
        } else {
          await _failBuildGate(
            task,
            runPk: runPk,
            reason:
                'The build gate (${status.wire}) failed on branch "$branch". '
                'Fix EVERY error/warning listed below, then resubmit.',
          );
        }
        return;
      }
    }
    debugPrint(
      '[Orchestrator p$projectId] task ${task.task_pk}: build run $runPk did not finish in time; failing the gate.',
    );
    await _failBuildGate(
      task,
      runPk: runPk,
      reason:
          'The build run did not finish within ${_buildTimeout.inMinutes} '
          'minutes and was treated as failed.',
    );
  }

  /// Send a task back to the board for a red build gate, FIRST attaching the
  /// failing run's full diagnostics (every analyze/compile error, not just the
  /// first) to the task description — so the worker fixes them ALL in one pass
  /// instead of one-error-per-resubmit.
  Future<void> _failBuildGate(Task task, {int? runPk, String? reason}) async {
    try {
      final errors = runPk != null ? await _collectBuildErrors(runPk) : '';
      final detail = [
        if (reason != null && reason.trim().isNotEmpty) reason.trim(),
        if (errors.isNotEmpty) errors,
      ].join('\n\n').trim();
      if (detail.isNotEmpty) {
        await _db.attachTaskBuildFailure(task.task_pk, detail);
      }
    } catch (e) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: could not attach build errors: $e',
      );
    }
    await _db.recordTaskBuildOutcome(task.task_pk, passed: false);
  }

  /// Pull every step log of [runPk] and return the diagnostic lines worth handing
  /// the worker — analyzer/compiler errors & warnings, test failures, file:line
  /// references — or the log tail when nothing matches the known shapes. Capped
  /// so a noisy log can't bloat the task description and the next prompt.
  Future<String> _collectBuildErrors(int runPk) async {
    final buf = StringBuffer();
    final jobs = await _db.getCiJobsForRun(runPk);
    for (final job in jobs) {
      final steps = await _db.getCiStepsForJob(job.ci_job_pk);
      for (final step in steps) {
        final log = step.logText.trim();
        if (log.isNotEmpty) buf.writeln(log);
      }
    }
    final lines = buf.toString().split('\n');
    final hits = lines
        .where((l) => _diagLineRe.hasMatch(l))
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList();
    final picked = hits.isNotEmpty
        ? hits
        : lines.reversed.take(40).toList().reversed.toList();
    var out = picked.join('\n').trim();
    const cap = 4000;
    if (out.length > cap) out = '…\n${out.substring(out.length - cap)}';
    return out;
  }

  // ── Merge stage ───────────────────────────────────────────────────────

  /// Spawn an ephemeral Coordinator to integrate a merge-ready [task]: merge
  /// `task/<id>` into its target branch (the parent task's branch for a subtask,
  /// otherwise main) and approve the task to Done. The Coordinator is the only
  /// role allowed to merge. If no Coordinator persona exists, the task is left
  /// awaiting a human merge.
  Future<void> _runMergeStage(Task task) async {
    _attempts[task.task_pk] = (_attempts[task.task_pk] ?? 0) + 1;
    final handles = await _resolveWorkspaceHandles();
    final git = handles.git;
    final lane = ref.read(gitLaneProvider(projectId));
    // A subtask integrates into its parent's branch; a top-level task into main.
    final targetBranch = await _integrationTargetBranch(task);
    final branch = task.workBranch ?? 'task/${task.task_pk}';

    await _db.beginTaskMerge(task.task_pk);

    // FAST PATH: a clean merge needs no agent — do it deterministically. The git
    // engine is conservative (it only reports a conflict when the SAME files
    // changed on both sides, and commits nothing in that case), so a non-conflict
    // outcome is safe to auto-approve. An agent is only pulled in for a real
    // conflict, exactly as the user expects. Serialized through the lane since it
    // mutates the shared tree/refs while other agents may be committing.
    if (git != null) {
      try {
        final result = await lane.run(() async {
          await _checkout(git, targetBranch, task.task_pk);
          return git.merge(
            branch,
            message: 'Merge task #${task.task_pk}: ${task.title}',
          );
        });
        if (result.outcome != MergeOutcome.conflicts) {
          await _db.approveTask(task.task_pk);
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: auto-merged (${result.outcome.name}) into "$targetBranch".',
          );
          return;
        }
        debugPrint(
          '[Orchestrator p$projectId] task ${task.task_pk}: merge conflicts on ${result.conflicts.length} file(s) — escalating.',
        );
      } catch (e) {
        debugPrint(
          '[Orchestrator p$projectId] task ${task.task_pk}: auto-merge errored ($e) — escalating.',
        );
      }
    }

    // CONFLICT PATH: a real conflict needs an agent (the Coordinator) to resolve
    // it or send the task back for rework. If there's no Coordinator persona,
    // don't stall forever — return the task to the board so the worker redoes it
    // against the now-updated target branch.
    final persona = await _findPersonaForRole(AgentRole.coordinator);
    if (persona == null) {
      await _db.reopenTask(task.task_pk);
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: merge conflict, no Coordinator persona; sent back to the board for rework.',
      );
      return;
    }
    final resolved = await _resolveBackend(persona);
    if (resolved == null) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: no inference server for coordinator ${persona.name}.',
      );
      return;
    }
    // Put the worktree on the target so the Coordinator resolves into it.
    await _checkout(handles.git, targetBranch, task.task_pk);

    final prompts = await _loadPrompts();
    final vars = _varsFor(task, branch, targetBranch: targetBranch);

    // Reuse the Coordinator's single per-agent session (see worker stage).
    final sessionPk = await _db.getOrCreateAgentChatSession(
      projectId,
      persona.agent_pk,
      persona.name,
    );

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
      systemPromptOverride: await _framedPrompt(
        AgentRole.coordinator,
        OrchestratorPromptField.mergeFraming,
        prompts,
        vars,
      ),
      enableThinking: resolveEnableThinking(
        agent: personaThinkingMode(
          persona.configJson,
          personaName: persona.name,
        ),
        task: ThinkingMode.fromString(task.thinkingMode),
      ),
    );

    var kickoff = prompts.render(OrchestratorPromptField.mergeKickoff, vars);
    for (var turn = 0; turn < _maxTurnsPerStage && !_disposed; turn++) {
      if (!await _stillRunning()) return;
      try {
        await for (final _ in session.runTurn(kickoff)) {}
      } catch (e) {
        if (_isNotTaskFault(e)) {
          _undoAttempt(task.task_pk); // backpressure/transient — don't penalize
        } else {
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: merge turn $turn failed: $e',
          );
        }
        return;
      }
      final fresh = await _db.getTaskById(task.task_pk);
      if (fresh == null) return;
      if (fresh.executionStatus == TaskExecStatus.done ||
          fresh.status == TaskStatus.todo) {
        debugPrint(
          '[Orchestrator p$projectId] task ${task.task_pk}: merge stage resolved (${fresh.executionStatus}).',
        );
        return;
      }
      kickoff = prompts.render(OrchestratorPromptField.mergeContinue, vars);
    }
    debugPrint(
      '[Orchestrator p$projectId] task ${task.task_pk}: merge hit turn cap without resolution.',
    );
  }

  // ── Templater stage (one-shot base scaffold + milestone planning) ───────

  /// Gate the pipeline on a scaffolded base project. Returns true when work may
  /// proceed (templating done, or not applicable to this project), false when it
  /// kicked off / is still running templating — the pump re-runs when it lands.
  Future<bool> _ensureTemplated(Project project) async {
    switch (project.templateStatus) {
      case 'ready':
      case 'none': // legacy / planning-path projects scaffold elsewhere
        return true;
      case 'failed':
        return false; // surfaced; a human re-runs templating to retry
      default: // 'pending' | 'scaffolding'
        if (_templating) return false;
        _templating = true;
        unawaited(
          _runTemplatingPhase(project).whenComplete(() {
            _templating = false;
            if (!_disposed) unawaited(_pump());
          }),
        );
        return false;
    }
  }

  /// One-shot pre-task phase: split the backlog into topic-grouped milestones,
  /// then have the Coordinator scaffold a compiling base project + a stub for each
  /// task and commit it to main. Success → templateStatus `ready` (workers start);
  /// a hard failure → `failed` (gated, surfaced to the human).
  Future<void> _runTemplatingPhase(Project project) async {
    try {
      await _assignMilestones();
      await _db.setProjectTemplateStatus(projectId, 'scaffolding');
      final scaffolded = await _runTemplaterAgent(project);
      if (!scaffolded) {
        await _db.setProjectTemplateStatus(projectId, 'failed');
        debugPrint('[Orchestrator p$projectId] templater could not scaffold; gated.');
        return;
      }
      // "Passes CI inspection": run the configured gate once against main (if any
      // task configured a workflow/dockerfile). No config → the compiling
      // scaffold is the bar and we proceed.
      final ciOk = await _runBaseCiGate(project);
      await _db.setProjectTemplateStatus(projectId, ciOk ? 'ready' : 'failed');
      debugPrint(
        '[Orchestrator p$projectId] templating done → ${ciOk ? 'ready' : 'failed'}.',
      );
    } catch (e, st) {
      debugPrint('[Orchestrator p$projectId] templating errored: $e\n$st');
      await _db.setProjectTemplateStatus(projectId, 'failed');
    }
  }

  /// Compute and persist each task's milestone batch (epic-aware, ceil(n/5)
  /// batches). Tasks under the same story epic stay together; the rest is split
  /// into roughly-even contiguous batches so no milestone runs too deep.
  Future<void> _assignMilestones() async {
    final tasks = await _db.getTasksForProject(projectId);
    if (tasks.isEmpty) {
      await _db.setProjectMilestonePlan(projectId, count: 0);
      return;
    }
    // Group key = each task's topmost story ancestor (its epic), so epic-mates
    // cluster. Tasks with no story are "loose" (null) and pack freely.
    final stories = await _db.getUserStoriesForProject(projectId);
    final parentOf = <int, int?>{for (final s in stories) s.story_pk: s.parent_story_fk};
    int? epicOf(int? storyPk) {
      if (storyPk == null) return null;
      var cur = storyPk;
      final seen = <int>{};
      while (parentOf[cur] != null && seen.add(cur)) {
        cur = parentOf[cur]!;
      }
      return cur;
    }

    final items = [
      for (final t in tasks)
        MilestoneItem(
          id: t.task_pk,
          groupKey: epicOf(t.task_story_fk),
          order: t.createdAt.millisecondsSinceEpoch,
        ),
    ];
    final assignment = assignMilestones(items);
    for (final entry in assignment.entries) {
      await _db.setTaskMilestone(entry.key, entry.value);
    }
    await _db.setProjectMilestonePlan(
      projectId,
      count: milestoneBatchCount(tasks.length),
    );
    debugPrint(
      '[Orchestrator p$projectId] milestones: ${tasks.length} tasks → '
      '${milestoneBatchCount(tasks.length)} batch(es).',
    );
  }

  /// Drive the Coordinator persona once to scaffold the base project onto main.
  /// Returns true when main has a commit (the scaffold landed).
  Future<bool> _runTemplaterAgent(Project project) async {
    final persona = await _findPersonaForRole(AgentRole.coordinator);
    if (persona == null) {
      debugPrint('[Orchestrator p$projectId] no Coordinator persona for templater.');
      return false;
    }
    final resolved = await _resolveBackend(persona);
    if (resolved == null) return false;
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final git = handles.git;
    if (ws == null || git == null) return false;

    // Scaffold onto main so every task branch (created off it) inherits the base.
    try {
      await git.checkoutBranch('main');
    } catch (_) {
      // No main yet — the scaffolder's first commit creates it.
    }

    final tasks = await _db.getTasksForProject(projectId);
    final taskList = tasks.map((t) => '- ${t.title}').join('\n');
    final prompts = await _loadPrompts();
    final vars = PromptVars(
      taskId: 0,
      title: project.name,
      branch: 'main',
      taskList: taskList,
    );

    final sessionPk = await _db.getOrCreateAgentChatSession(
      projectId,
      persona.agent_pk,
      persona.name,
    );
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
      workspace: ws,
      git: git,
      buildService: handles.build,
      leanTools: false,
      systemPromptOverride: await _framedPrompt(
        AgentRole.coordinator,
        OrchestratorPromptField.templaterFraming,
        prompts,
        vars,
      ),
      enableThinking: resolveEnableThinking(
        agent: personaThinkingMode(persona.configJson, personaName: persona.name),
        task: ThinkingMode.off,
      ),
    );

    var kickoff = prompts.render(OrchestratorPromptField.templaterKickoff, vars);
    for (var turn = 0; turn < _maxTurnsPerStage && !_disposed; turn++) {
      if (!await _stillRunning()) return false;
      try {
        await for (final _ in session.runTurn(kickoff)) {}
      } catch (e) {
        if (!_isNotTaskFault(e)) {
          debugPrint('[Orchestrator p$projectId] templater turn $turn failed: $e');
          return (await git.headOid()) != null;
        }
        // transient/backpressure — retry the turn.
      }
      if ((await git.headOid()) != null) return true; // scaffold committed
      kickoff =
          'Continue creating any remaining base/stub files, then commit with '
          'git_commit. Stop once the skeleton compiles and every task has a stub.';
    }
    return (await git.headOid()) != null;
  }

  /// Run the project's configured CI once against main as the base gate. Honors
  /// the per-task build config: if no task configured a workflow/dockerfile,
  /// there's nothing to run and the gate passes (the compiling scaffold is the
  /// bar). Returns true on green / nothing-to-run, false on a red run.
  Future<bool> _runBaseCiGate(Project project) async {
    final tasks = await _db.getTasksForProject(projectId);
    Task? cfg;
    for (final t in tasks) {
      final wf = t.workflowPath?.trim() ?? '';
      final df = t.dockerfilePath?.trim() ?? '';
      if (wf.isNotEmpty || df.isNotEmpty) {
        cfg = t;
        break;
      }
    }
    if (cfg == null) return true;
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final build = handles.build;
    if (ws == null || build == null) return true; // can't run → don't block
    final workflowPath = cfg.workflowPath?.trim() ?? '';
    final dockerfilePath = cfg.dockerfilePath?.trim() ?? '';
    int runPk;
    try {
      if (workflowPath.isNotEmpty) {
        runPk = (await build.startWorkflowRun(
          clientPk: project.client_fk,
          projectPk: projectId,
          ws: ws,
          workflowPath: workflowPath,
          branch: 'main',
          triggeredBy: 'templater',
        )).runPk;
      } else {
        runPk = (await build.startDockerBuild(
          clientPk: project.client_fk,
          projectPk: projectId,
          ws: ws,
          dockerfilePath: dockerfilePath,
          imageTag: 'base:latest',
          branch: 'main',
          triggeredBy: 'templater',
        )).runPk;
      }
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] base CI failed to start: $e');
      return false;
    }
    final deadline = DateTime.now().add(_buildTimeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_buildPollInterval);
      final run = await _db.getCiRun(runPk);
      if (run == null) break;
      final status = CiStatusX.fromWire(run.status);
      if (status.isTerminal) return status == CiStatus.success;
    }
    return false;
  }

  /// Advance to the next milestone batch once every task in the current-or-earlier
  /// batches is finished. A Blocked task is surfaced to the human and does NOT
  /// freeze the project. No-op for single-batch (short) projects or the last batch.
  Future<void> _maybeAdvanceMilestone(Project project) async {
    final count = project.milestoneCount;
    if (count <= 1) return;
    final current = project.currentMilestone;
    if (current >= count - 1) return;
    final tasks = await _db.getTasksForProject(projectId);
    final inScope = tasks.where((t) => (t.milestoneOrder ?? 0) <= current);
    if (inScope.isEmpty) return;
    final pending = inScope.where(
      (t) => t.status != TaskStatus.done && t.status != TaskStatus.blocked,
    );
    if (pending.isNotEmpty) return;
    final next = await _db.advanceProjectMilestone(projectId);
    debugPrint(
      '[Orchestrator p$projectId] milestone $current complete → opening '
      '$next/${count - 1}.',
    );
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
  Future<({Workspace? ws, NxtprjGitEngine? git, BuildService? build})>
  _resolveWorkspaceHandles() async {
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

  /// Isolated handles for a CONCURRENT task stage: the task's own working tree,
  /// the shared git engine (objects/refs), and the per-project lane that
  /// serializes shared-DB writes. Null if the workspace can't be opened.
  Future<
    ({
      Workspace tree,
      NxtprjGitEngine git,
      AsyncLock lane,
      BuildService? build,
    })?
  >
  _resolveTaskHandles(int taskPk) async {
    try {
      final tree = await ref.read(
        taskWorkspaceProvider((projectId: projectId, taskPk: taskPk)).future,
      );
      final git = await ref.read(gitEngineProvider(projectId).future);
      final lane = ref.read(gitLaneProvider(projectId));
      final build = ref.read(buildServiceProvider);
      return (tree: tree, git: git, lane: lane, build: build);
    } catch (e) {
      debugPrint(
        '[Orchestrator p$projectId] task $taskPk: task workspace unavailable: $e',
      );
      return null;
    }
  }

  /// Dispose + delete a finished task's isolated working tree. The committed
  /// work lives on the task branch in the shared object DB, so the scratch tree
  /// is disposable.
  Future<void> _releaseTaskTree(int taskPk) async {
    ref.invalidate(
      taskWorkspaceProvider((projectId: projectId, taskPk: taskPk)),
    );
    await deleteTaskDisk(projectId, taskPk);
  }

  /// True if [e] is the plan's concurrent-connection cap (HTTP 429 /
  /// too_many_connections). Records a short dispatch backoff so the pump stops
  /// launching new agents until a connection frees. This is BACKPRESSURE, not a
  /// task failure — callers return the task to the board and never Block it.
  bool _isConnCap(Object e) {
    final hit =
        e is LemonadeApiException &&
        (e.statusCode == 429 ||
            e.message.toLowerCase().contains('too_many_connections'));
    if (hit) {
      _connBackoffUntil = DateTime.now().add(_connBackoff);
      debugPrint(
        '[Orchestrator p$projectId] connection cap (429) — returning task to '
        'the board, pausing new agents for ${_connBackoff.inSeconds}s.',
      );
    }
    return hit;
  }

  /// True if [e] is a TRANSIENT upstream/server hiccup (502/503/504) — the
  /// gateway momentarily couldn't serve the request. Like 429, this is NOT the
  /// task's fault, so it must not burn the retry budget; the caller undoes the
  /// attempt and the task is retried.
  static bool _isTransientServer(Object e) =>
      e is LemonadeApiException &&
      (e.statusCode == 502 || e.statusCode == 503 || e.statusCode == 504);

  /// Backpressure (429) OR a transient 5xx — neither should count as a failed
  /// attempt against the task.
  bool _isNotTaskFault(Object e) => _isConnCap(e) || _isTransientServer(e);

  /// Undo one attempt for [taskPk] (used when a turn failed for a reason that
  /// isn't the task's fault, so a flaky gateway can't drive it to Blocked).
  void _undoAttempt(int taskPk) {
    final n = (_attempts[taskPk] ?? 1) - 1;
    if (n <= 0) {
      _attempts.remove(taskPk);
    } else {
      _attempts[taskPk] = n;
    }
  }

  /// How many agents may run at once: the routed (subscription) server's
  /// `maxConcurrency` (synced from the account), clamped to a safe range. Falls
  /// back to 1 when no server is configured.
  Future<int> _concurrencyCap(Project project) async {
    try {
      final servers = await _db.getInferenceServersForClient(project.client_fk);
      if (servers.isEmpty) return 1;
      final routed = servers.where((s) => isRoutedProviderType(s.providerType));
      final n =
          (routed.isNotEmpty ? routed.first : servers.first).maxConcurrency;
      return n.clamp(1, 12);
    } catch (_) {
      return 1;
    }
  }

  /// Put the worktree on [branch], creating it if needed. When the branch must
  /// be created and [base] is given (and exists), the worktree is first switched
  /// to [base] so the new branch diverges from it — this is how a subtask branch
  /// is rooted on its parent's branch. No-op when git is null.
  Future<void> _checkout(
    NxtprjGitEngine? git,
    String branch,
    int taskPk, {
    String? base,
  }) async {
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
      debugPrint(
        '[Orchestrator p$projectId] task $taskPk: checkout "$branch" failed: $e',
      );
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
  Future<({InferenceBackend client, String? model})?> _resolveBackend(
    AgentPersona persona,
  ) async {
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

    final models = chosen.availableModelsJson.isNotEmpty
        ? (jsonDecode(chosen.availableModelsJson) as List).cast<String>()
        : const <String>[];

    // Address the model the SAME way the app/coordinator does. The routed Nexus
    // Router serves the Omni COLLECTION id (LMX-Omni-52B-Halo) DIRECTLY, so send
    // it as-is and default to it — never decompose to a raw sub-model, which fell
    // through to a small 4B (e.g. Qwen3.5-4B): the wrong model, and (when the
    // routed server had no selected model) the null→'default-coordinator'
    // sentinel that 503'd and Blocked every task. Local servers (which 500 on a
    // bare collection) decompose from their live model list instead.
    final routed = isRoutedProviderType(chosen.providerType);
    List<ApiModelInfo> serverModels = const [];
    if (!routed) {
      final cache = ref.read(aiServersCacheProvider.notifier);
      var entry = cache.entryFor(chosen.server_pk);
      if (entry == null || entry.models.isEmpty) {
        await cache.refreshServer(chosen.server_pk);
        entry = cache.entryFor(chosen.server_pk);
      }
      serverModels = entry?.models ?? const <ApiModelInfo>[];
    }
    // Resolve the worker's model the SAME way the coordinator/setup now do: honor
    // the persona's own Omni collection (its per-role default — e.g. a dedicated
    // coding collection), not just the global product default. On the routed
    // Router the collection id is sent as-is; an explicit per-persona llmModel
    // still wins. Local servers decompose from their live model list.
    final personaCollection = persona.omniCollectionModel;
    final collection =
        (personaCollection != null && personaCollection.trim().isNotEmpty)
        ? personaCollection.trim()
        : defaultOmniCollectionForTitle(persona.title);
    final pLlm = persona.llmModel;
    final model = routed
        ? ((pLlm != null && pLlm.trim().isNotEmpty) ? pLlm.trim() : collection)
        : resolveAgentChatModel(
            routed: false,
            personaModel: pLlm,
            selectedModel: chosen.selectedModel,
            serverModels: serverModels,
          );
    debugPrint(
      '[Orchestrator p$projectId] worker "${persona.name}" → server '
      '"${chosen.name}" model=$model (routed=$routed, collection=$collection)',
    );

    final uiServer = ui_server.InferenceServer(
      id: chosen.server_pk.toString(),
      name: chosen.name,
      baseUrl: chosen.baseUrl,
      apiKey: chosen.apiKey,
      providerType: 'lemonade',
      selectedModel: chosen.selectedModel,
      availableModels: models,
    );
    // Per-agent session id → the Router gives each agent its own warm backend and
    // spreads different agents across the fleet (agent 1..N → server 1..N), instead
    // of every agent piling onto one box.
    return (
      client: backendForServer(uiServer,
          agentName: persona.name, sessionId: 'agent-${persona.agent_pk}'),
      model: model,
    );
  }
}

/// The pipeline stage a task is ready for, in execution order.
enum _Stage { implement, verify, build, merge }

/// One [ProjectOrchestrator] per project. AUTO-DISPOSED: it lives only while the
/// project is FOCUSED (the shell + workspace watch the current project's
/// orchestrator). Switching to another project disposes this one, so the old
/// project stops spawning agents and stops competing for the connection budget —
/// it self-starts again (and resumes if still `running`) when you refocus it.
final projectOrchestratorProvider =
    Provider.autoDispose.family<ProjectOrchestrator, int>((ref, projectId) {
      final orchestrator = ProjectOrchestrator(ref, projectId)..start();
      ref.onDispose(orchestrator.dispose);
      return orchestrator;
    });
