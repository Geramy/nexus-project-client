// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

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
    show
        resolveAgentChatModel,
        defaultOmniCollectionForTitle,
        pickRoutedCollectionId;
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
///   2. **Verify (lightweight review)** — per-task review runs NO build. A task
///      with a functional `verification` gets a short Verification Agent that
///      reads the changed code to confirm the behavior; everything else passes
///      immediately. The project's CI/test runs ONCE at the end (see
///      [_maybeFinalizeProject]) rather than per task.
///   3. **Build** — legacy/explicit per-task build gate for a verified task that
///      still carries `requiresBuild`; stage 2 advances such tasks straight to
///      `built`, so this effectively never runs in the default pipeline.
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

  /// LEARNED file footprint per task: every workspace path a task has touched —
  /// claimed OR been denied — accumulated across ALL its attempts (unlike
  /// [_fileOwners], which is dropped the moment a non-submitting run releases).
  /// This is what makes scheduling PREDICTIVE instead of reactive: once we know
  /// two tasks edit overlapping files, the dispatcher refuses to run them at the
  /// same time (see [_scopeConflict]) so the second waits cleanly on the board
  /// instead of starting, colliding mid-edit, and throwing away its exploration.
  /// Reset on dispose; an entry is dropped once its task reaches Done/Blocked.
  final Map<int, Set<String>> _taskFootprint = {};

  /// True if dispatching [taskPk] now would collide with work already in flight,
  /// based on its LEARNED footprint: a file it is known to touch is currently
  /// locked by another task (active or awaiting merge), OR its footprint overlaps
  /// the footprint of a currently-active task. A task whose footprint is still
  /// unknown (never run) returns false — first run is unconstrained, and the
  /// collision it may hit teaches us the overlap for next time.
  bool _scopeConflict(int taskPk) {
    final mine = _taskFootprint[taskPk];
    if (mine == null || mine.isEmpty) return false;
    for (final f in mine) {
      final owner = _fileOwners[f];
      if (owner != null && owner != taskPk) return true; // file held by another
    }
    for (final other in _active) {
      if (other == taskPk) continue;
      final theirs = _taskFootprint[other];
      if (theirs != null && mine.any(theirs.contains)) return true; // overlap
    }
    return false;
  }

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

  /// Signature of the completed-task set the last GREEN end-of-project scan ran
  /// against, so a passed project isn't re-scanned every tick — only when the
  /// done set actually changes (a task reopened+refixed, or new work completed).
  String? _finalScanPassedSig;

  // ── End-of-project TESTING phase ────────────────────────────────────────
  // Once every task is done, the project enters a dedicated TESTING phase (like
  // the yellow Templating stage — NOT a task): it repeatedly runs CI on main and,
  // on RED, drives ONE focused fix agent (the strongest model, given ALL the
  // failpoints at once) to fix the WHOLE project before the next CI run, then
  // re-scans — looping until green. This replaces the old "reopen one task
  // forever" thrash, which only used a single connection (one task = one conn).
  //
  // It keeps going as long as it's making PROGRESS (fewer failpoints each CI
  // run); it only gives up after the failure count fails to drop for
  // [_maxStagnantRounds] consecutive rounds — so the user doesn't have to step in
  // while it's still improving. [_absoluteMaxTestingRounds] is a hard backstop
  // against a pathological infinite loop.
  static const int _maxStagnantRounds = 6;
  static const int _absoluteMaxTestingRounds = 40;
  /// Per-CI-run failpoint payload cap handed to the fixer — generous so e.g. 100
  /// failures all go in ONE pass (fix them all, THEN re-run CI; don't test after
  /// every point).
  static const int _maxFixErrorChars = 24000;
  /// The fix agent's per-invocation turn budget — high enough to work across many
  /// files in a single pass before the next CI run.
  static const int _maxFixAgentTurns = 24;
  /// Running guard so only one TESTING phase runs at a time (mirrors _templating).
  bool _testing = false;
  /// Live phase flag + detail mirrored into [orchestratorStatusProvider] so the
  /// top-bar shows a yellow "Testing" stage while it runs.
  bool _testingActive = false;
  String? _testingDetail;
  /// Done-set signature the testing loop exhausted its rounds on, so we don't
  /// immediately re-enter the (slow) loop for the same unchanged red state.
  String? _testingExhaustedSig;

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

  /// Functional review is a quick spot-check (the build gate already proved it
  /// compiles), so the Verification Agent gets only a few turns — not the full
  /// stage budget — keeping review the fastest step.
  static const int _maxFunctionalVerifyTurns = 3;

  /// The project's default deterministic CI gate, scaffolded once by the Templater
  /// (see [_ensureDefaultCiWorkflow]) and run with NO LLM by both per-task review
  /// and the end-of-project scan.
  static const String _defaultCiPath = '/.github/workflows/ci.yml';
  static const Duration _connBackoff = Duration(seconds: 20);

  /// Idle-timeout watchdog for a single agent turn: if the model/stream produces
  /// NO event for this long, the turn is considered stalled (a backend that
  /// accepted the connection but never streams — the "hung worker that never
  /// frees its slot, so the loop stops" failure) and is aborted. The task yields
  /// back (NOT penalized — a stall isn't its fault), the slot frees, and the pump
  /// moves on. Generous so a slow-but-working turn under load is never killed.
  static const Duration _turnIdleTimeout = Duration(minutes: 4);
  /// Safety valve for the shared git lane: a single materialize/commit/merge
  /// that hangs would wedge the lane (and so freeze EVERY task's git step) until
  /// the app restarts. Cap how long any one lane op may hold the mutex so the
  /// lane self-heals. Generous — a real merge under load finishes in seconds.
  static const Duration _laneOpTimeout = Duration(minutes: 4);
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
    // AUTO-START TESTING: if a project is loaded with every task already done but
    // not yet CI-validated, the only work left is the end-of-project Testing gate
    // — begin it automatically on load instead of making the user press Start.
    unawaited(_maybeAutoStartTesting());
  }

  /// Auto-resume a loaded project straight into the TESTING phase when all its
  /// tasks are done but CI hasn't passed (it isn't `completed`). The sole
  /// remaining work is the CI/fix gate, so there's nothing for the user to
  /// "Start" — flip it to `running` and let the normal pump drive testing.
  Future<void> _maybeAutoStartTesting() async {
    try {
      if (_disposed) return;
      final project = await _db.getProjectById(projectId);
      if (project == null) return;
      // Already finished, or already running (the pump handles it) — nothing to do.
      final state = project.orchestrationState;
      if (state == 'completed' || state == 'running') return;
      // Only when the backlog is fully done AND we're on the last milestone — i.e.
      // the project is genuinely at the end-of-project gate, not mid-build (we
      // must NOT auto-resume an in-progress build the user deliberately paused).
      if (project.currentMilestone < project.milestoneCount - 1) return;
      final tasks = await _db.getTasksForProject(projectId);
      if (tasks.isEmpty) return;
      final allDone = tasks.every((t) => t.status == TaskStatus.done);
      if (!allDone) return;
      debugPrint(
        '[Orchestrator p$projectId] all tasks done but CI not validated → '
        'auto-starting the Testing phase on load.',
      );
      await _db.setProjectOrchestrationState(projectId, 'running');
      if (!_disposed) unawaited(_pump());
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] auto-start testing check failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _projectSub?.cancel();
    _ticker?.cancel();
    // Drop all file claims so a fresh orchestrator (e.g. after a project swap)
    // never inherits a stale lock — the anti-hog reset.
    _fileOwners.clear();
    _taskFootprint.clear();
  }

  /// Fill up to N agent slots (N = the account's max concurrency) with the next
  /// fair, backlog-weighted pieces of work, launching each on its own isolated
  /// working tree. Returns immediately after dispatching; each stage frees its
  /// slot and re-pumps on completion. [_pumping] guards only the dispatch loop,
  /// not the work, so it never serializes the agents.
  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    var advancedMilestone = false;
    var spawnedFixWork = false;
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
      advancedMilestone = await _maybeAdvanceMilestone(project, workerCap);
      spawnedFixWork = await _maybeFinalizeProject(project);
      await _publishSlotStatus(workerCap);
    } finally {
      _pumping = false;
    }
    // A just-opened milestone OR a freshly-spawned fix batch has new assignable
    // work — re-pump now to fill the idle slots immediately instead of waiting
    // for the next 30s tick.
    if ((advancedMilestone || spawnedFixWork) && !_disposed) {
      unawaited(_pump());
    }
  }

  /// Publish a live snapshot of worker-slot usage so the UI can show WHY a slot is
  /// idle — most often a startable task HELD BACK because its files overlap work
  /// in flight (the predictive scope gate) — instead of silently showing fewer
  /// agents than the plan allows. [workerSlots] is the worker pool (cap minus the
  /// reserved Coordinator slot).
  Future<void> _publishSlotStatus(int workerSlots) async {
    if (_disposed) return;
    try {
      final tasks = await _db.getTasksForProject(projectId);
      final currentMilestone =
          (await _db.getProjectById(projectId))?.currentMilestone ?? 0;
      final waiting = <OrchestratorWait>[];
      for (final t in tasks) {
        if (t.task_agent_fk == null) continue;
        if (_active.contains(t.task_pk)) continue;
        if ((t.milestoneOrder ?? 0) > currentMilestone) continue;
        if ((_attempts[t.task_pk] ?? 0) >= _maxAttemptsPerTask) continue;
        final startable =
            t.status == TaskStatus.todo &&
            (t.executionStatus == TaskExecStatus.idle ||
                t.executionStatus == TaskExecStatus.queued ||
                t.executionStatus == TaskExecStatus.failed);
        if (!startable) continue;
        // Only report tasks that are ready but BLOCKED by file-scope overlap — a
        // plain queued task that simply hasn't been reached yet isn't "held".
        if (!_scopeConflict(t.task_pk)) continue;
        final mine = _taskFootprint[t.task_pk] ?? const <String>{};
        String? heldFile;
        int? owner;
        for (final f in mine) {
          final o = _fileOwners[f];
          if (o != null && o != t.task_pk) {
            heldFile = f;
            owner = o;
            break;
          }
        }
        waiting.add(
          OrchestratorWait(
            taskPk: t.task_pk,
            agentFk: t.task_agent_fk,
            reason: heldFile != null
                ? 'needs "${heldFile.split('/').last}" held by task #$owner'
                : 'its files overlap a task in flight',
          ),
        );
      }
      ref.read(orchestratorStatusProvider(projectId).notifier).state =
          OrchestratorStatus(
            workerSlots: workerSlots,
            activeStages: _active.length,
            waiting: waiting,
            testing: _testingActive,
            testingDetail: _testingDetail,
          );
    } catch (_) {
      // Status is best-effort telemetry; never let it disturb the pump.
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
        // A task that has PASSED review (verified / built) is NOT stalled — it
        // just needs the deterministic merge, which must never be blocked by the
        // retry budget (that's what wrongly Blocked a passed task at the finish
        // line). Only block tasks still TRYING to pass: on the board (todo), or
        // stuck getting a verdict / re-driving a conflict (submitted / verifying
        // / merging).
        final stalled =
            t.status == TaskStatus.todo ||
            (t.status == TaskStatus.review &&
                (t.executionStatus == TaskExecStatus.submitted ||
                    t.executionStatus == TaskExecStatus.verifying ||
                    t.executionStatus == TaskExecStatus.merging));
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

      // Forget the footprint of any task that's finished for good (Done/Blocked
      // and not running) — it can never collide again, so its scope shouldn't
      // keep gating others, and the map stays bounded over a long project.
      if (_taskFootprint.isNotEmpty) {
        for (final t in tasks) {
          if ((t.status == TaskStatus.done || t.status == TaskStatus.blocked) &&
              !_active.contains(t.task_pk)) {
            _taskFootprint.remove(t.task_pk);
          }
        }
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
          .where(
            (t) =>
                // A task that PASSED review (built, or verified without a build
                // gate) ALWAYS gets its merge — the deterministic fast-path is
                // quick, so it's never gated by the retry budget (gating it there
                // stranded passed tasks at the finish line). Only the conflict
                // re-drive (`merging`, an interrupted/escalated coordinator merge)
                // stays budget-bounded so a stuck merge can't loop forever.
                t.executionStatus == TaskExecStatus.built ||
                (t.executionStatus == TaskExecStatus.verified &&
                    !t.requiresBuild) ||
                (t.executionStatus == TaskExecStatus.merging && live(t)),
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
      // Predictive scope gate: don't start a task that's known to edit files
      // another in-flight task holds — it would only collide and park. Leave it
      // on the board; it dispatches cleanly once the conflicting task merges.
      if (_scopeConflict(t.task_pk)) {
        debugPrint(
          '[Orchestrator p$projectId] task ${t.task_pk}: held back — its file '
          'scope overlaps work in flight; waiting for a clean slot.',
        );
        continue;
      }
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

    final resolved = await _resolveBackend(persona, taskPk: task.task_pk);
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
    // PRESERVE WORK ON RESUME: a task that was parked/yielded mid-build (exec
    // `queued`) and already has commits on its branch keeps them — we just rebuild
    // its scratch tree from the branch and continue, instead of tossing the work
    // and redoing from scratch. (Staleness vs the latest base is reconciled at
    // merge time, which escalates only real same-file conflicts.) A fresh task
    // (no branch yet) is rooted on its base; a rework after a real merge conflict
    // or failed gate (exec idle/failed) re-roots onto the CURRENT target so the
    // redo rebases cleanly.
    final branchExists = (await th.git.branches()).contains(branch);
    final preserveWork =
        branchExists && task.executionStatus == TaskExecStatus.queued;
    // Root the task branch / hydrate its tree, serialized through the lane (the
    // shared object/ref DB is single-isolate). This runs OUTSIDE the turn loop,
    // so the SSE watchdog doesn't cover it — guard it with the lane timeout so a
    // hung git step yields the task back instead of wedging the lane (and every
    // other task's git op) until restart.
    try {
      await th.lane.run(() async {
        if (preserveWork) {
          await th.git.materializeInto(branch, th.tree);
        } else {
          await th.git.deleteBranch(branch);
          await th.git.createBranchAt(branch, base: base);
          await th.git.materializeInto(branch, th.tree);
        }
      }, timeout: _laneOpTimeout);
    } catch (e) {
      // A hang (TimeoutException) or transient git error here isn't the task's
      // fault — release locks/tree and yield back so the pump moves on.
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: branch setup '
        '${e is TimeoutException ? 'timed out' : 'failed'} ($e) — yielding back.',
      );
      _releaseLocks(task.task_pk);
      await _releaseTaskTree(task.task_pk);
      await _db.markTaskYieldedBack(task.task_pk);
      return;
    }
    if (preserveWork) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: resuming on its '
        'existing branch — prior work preserved.',
      );
    }

    // File-claim queue: claim a file the first time this worker edits it; if
    // another task holds it, deny (the tool returns a "queued" message) and flag
    // the task to PARK. Locks are kept past submission (until merge) so no two
    // tasks submit conflicting edits to the same file; a non-submitting run
    // releases them in the finally below. Declared OUTSIDE the try so the finally
    // can read `submitted`.
    var parked = false;
    var submitted = false;
    // Whether this run was granted at least one file to edit — i.e. it may have
    // produced uncommitted changes worth checkpointing if it then parks.
    var madeEdit = false;
    bool claim(String path) {
      final p = _normFile(path);
      // Learn this task's footprint whether the claim is granted or denied — a
      // denied file is one it WANTS, so it counts toward future scope conflicts.
      (_taskFootprint[task.task_pk] ??= <String>{}).add(p);
      final owner = _fileOwners[p];
      if (owner == null || owner == task.task_pk) {
        _fileOwners[p] = task.task_pk;
        madeEdit = true;
        return true;
      }
      parked = true;
      return false;
    }

    try {
      final prompts = await _loadPrompts();
      final vars = _varsFor(task, branch, targetBranch: base);
      // Give the worker PROJECT-WIDE CONTEXT (the task decomposition + the current
      // file tree + stay-in-your-lane rules) so parallel tasks build on each other
      // instead of each silo re-creating and overwriting shared files.
      final projectContext = await _buildWorkerProjectContext(task, th.tree);

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
        systemPromptOverride:
            '${await _framedPrompt(role, OrchestratorPromptField.workerFraming, prompts, vars)}'
            '\n\n$projectContext',
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
              // Reading a provider after the orchestrator was disposed throws —
              // skip the capture in that case.
              if (_disposed || !ref.read(workerCaptureProvider)) return;
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
          ).timeout(_turnIdleTimeout)) {
            // Drain the stream; tool effects are applied inside runTurn.
          }
        } catch (e) {
          if (e is TimeoutException) {
            // The turn stalled — a backend that took the connection but never
            // streamed. NOT the task's fault: undo the attempt and yield back so
            // the slot frees and the pump moves on (instead of hanging forever).
            _undoAttempt(task.task_pk);
            debugPrint(
              '[Orchestrator p$projectId] task ${task.task_pk}: turn $turn stalled '
              '(no stream for ${_turnIdleTimeout.inMinutes}m) — aborting, yielding back.',
            );
          } else if (_isNotTaskFault(e)) {
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
        // it waits. HOLD ITS WORK, don't toss it: checkpoint any uncommitted
        // edits onto the task branch so the resume continues from here (the
        // resume preserves the branch instead of re-rooting — see above).
        if (parked) {
          if (madeEdit) {
            try {
              await th.lane.run(
                () => th.git.commitFrom(
                  th.tree,
                  branch: branch,
                  message:
                      'wip: checkpoint before pausing for a held file (task #${task.task_pk})',
                ),
                timeout: _laneOpTimeout,
              );
            } catch (e) {
              debugPrint(
                '[Orchestrator p$projectId] task ${task.task_pk}: could not checkpoint parked work: $e',
              );
            }
          }
          _undoAttempt(task.task_pk);
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: parked — a file it '
            'needs is held by another task; work preserved, will resume after that task merges.',
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

  /// PROJECT-WIDE CONTEXT for a worker: the full task decomposition + the current
  /// file tree (from its own branch) + the "stay in your lane" rules. Without this
  /// a worker only sees its single task and the stack, so with more tasks each
  /// silo re-creates and overwrites the shared/glue files the others also touch —
  /// the "more tasks = more overwriting" failure. Caps keep it cheap to inject on
  /// every worker turn even on a large backlog.
  Future<String> _buildWorkerProjectContext(Task task, Workspace tree) async {
    final b = StringBuffer();
    try {
      final tasks = await _db.getTasksForProject(projectId)
        ..sort((a, c) => a.task_pk.compareTo(c.task_pk));
      b.writeln(
        '=== PROJECT TASK MAP (the full decomposition — build ON these; do NOT '
        'redo or duplicate another task\'s work) ===',
      );
      const taskCap = 80;
      var shown = 0;
      for (final t in tasks) {
        if (shown >= taskCap) {
          b.writeln('… (+${tasks.length - taskCap} more tasks)');
          break;
        }
        shown++;
        final mark = t.task_pk == task.task_pk ? '   ← THIS TASK' : '';
        b.writeln('- #${t.task_pk} [${t.status}] ${t.title}$mark');
      }
    } catch (_) {}
    try {
      final files = (await tree.walk())
          .where((f) => !f.isDirectory)
          .map((f) => f.path)
          .toList()
        ..sort();
      if (files.isNotEmpty) {
        b.writeln(
          '\n=== CURRENT PROJECT FILES (already on your branch — read what you '
          'need; do NOT re-list directories) ===',
        );
        const fileCap = 200;
        for (var i = 0; i < files.length && i < fileCap; i++) {
          b.writeln(files[i]);
        }
        if (files.length > fileCap) {
          b.writeln('… (+${files.length - fileCap} more files)');
        }
      }
    } catch (_) {}
    b.write('''

=== STAY IN YOUR LANE (this is how parallel tasks avoid overwriting each other) ===
- Implement ONLY your task's artifact (the file[s] this task is about). Other tasks own the other files — do NOT rewrite or "improve" a file that belongs to another task.
- When you need something another task provides (a model, service, route, widget), reference it by its expected name/path as an interface — do NOT recreate it. If it isn't there yet, code against the interface the task map implies; integration happens at merge.
- For a SHARED/glue file many tasks touch (a router, DI/service registration, barrel export, schema), make the SMALLEST ADDITIVE change (add your entry) — never rewrite or reformat the whole file.''');
    return b.toString().trimRight();
  }

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

  /// REVIEW. The project's CI/test gate is consolidated into a SINGLE end-of-
  /// project scan ([_maybeFinalizeProject]) — for a mostly-automated pipeline,
  /// testing once at the end is far faster than a full build per task. So per-task
  /// review runs NO build: a task with a real functional `verification` gets a
  /// short Verification Agent to confirm the described behavior; anything else
  /// passes immediately. Compile/test correctness is enforced once, at the end.
  Future<void> _runVerifyStage(Task task) async {
    // Count this Review attempt against the retry budget so a task that can
    // never get a verdict is surfaced to Blocked instead of cycling forever.
    _attempts[task.task_pk] = (_attempts[task.task_pk] ?? 0) + 1;
    final branch = task.workBranch ?? 'task/${task.task_pk}';

    final verification = (task.verification ?? '').trim();
    if (verification.isEmpty) {
      // Nothing functional to confirm — pass immediately (the end-of-project CI
      // scan is the test gate). This is the fast path for most tasks.
      await _db.recordTaskVerdict(task.task_pk, passed: true);
      if (task.requiresBuild) {
        await _db.recordTaskBuildOutcome(task.task_pk, passed: true);
      }
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: review passed (no functional verification; CI runs at project end).',
      );
      return;
    }
    await _runFunctionalVerify(task, branch);
  }

  /// Spawn a SHORT Verification Agent to confirm the task's FUNCTIONAL behavior
  /// by reading the changed code (it must NOT run the build/CI — tests run once at
  /// project end). On a pass for a `requiresBuild` task the result is advanced to
  /// `built` so the legacy build stage stays out of the way. Falls through to a
  /// pass when no verifier persona exists.
  Future<void> _runFunctionalVerify(Task task, String branch) async {
    final persona = await _findPersonaForRole(AgentRole.verificationAgent);
    if (persona == null) {
      // No verifier persona — pass it through (the end-of-project scan is the net).
      await _db.recordTaskVerdict(task.task_pk, passed: true);
      if (task.requiresBuild) {
        await _db.recordTaskBuildOutcome(task.task_pk, passed: true);
      }
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: no verifier persona; review passed.',
      );
      return;
    }
    final resolved = await _resolveBackend(persona, taskPk: task.task_pk);
    if (resolved == null) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: no inference server for verifier ${persona.name}.',
      );
      return;
    }
    final th = await _resolveTaskHandles(task.task_pk);
    if (th == null) return;
    // Hydrate an isolated tree with the submitted task branch so the verifier
    // reads the work without touching any other agent's tree. Guard the lane op
    // (a hang here would wedge the lane for every task) — on timeout/error yield
    // back so the task stays in Review and the pump retries it.
    try {
      await th.lane.run(
        () => th.git.materializeInto(branch, th.tree),
        timeout: _laneOpTimeout,
      );
    } catch (e) {
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: verify hydrate '
        '${e is TimeoutException ? 'timed out' : 'failed'} ($e) — yielding back.',
      );
      await _releaseTaskTree(task.task_pk);
      // A lane hang is infra, not the task's fault — un-count this Review attempt
      // so a transient freeze can't push a good task toward Blocked. The task is
      // still `submitted` (verifying isn't marked until below), so the verify
      // pool re-picks it next pump on the now self-healed lane.
      _undoAttempt(task.task_pk);
      return;
    }

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
      for (var turn = 0;
          turn < _maxFunctionalVerifyTurns && !_disposed;
          turn++) {
        if (!await _stillRunning()) return;
        try {
          await for (final _ in session.runTurn(kickoff).timeout(_turnIdleTimeout)) {}
        } catch (e) {
          if (e is TimeoutException || _isNotTaskFault(e)) {
            _undoAttempt(task.task_pk); // stall/backpressure/transient — don't penalize
          } else {
            debugPrint(
              '[Orchestrator p$projectId] task ${task.task_pk}: functional verify turn $turn failed: $e',
            );
          }
          return;
        }
        final fresh = await _db.getTaskById(task.task_pk);
        if (fresh == null) return;
        if (fresh.executionStatus != TaskExecStatus.submitted &&
            fresh.executionStatus != TaskExecStatus.verifying) {
          // A functional PASS on a build-gated task jumps to `built` so the legacy
          // build stage doesn't re-run anything (CI is the end-of-project scan).
          if (fresh.executionStatus == TaskExecStatus.verified &&
              task.requiresBuild) {
            await _db.recordTaskBuildOutcome(task.task_pk, passed: true);
          }
          debugPrint(
            '[Orchestrator p$projectId] task ${task.task_pk}: functional verdict recorded (${fresh.executionStatus}).',
          );
          return;
        }
        kickoff = prompts.render(OrchestratorPromptField.verifyContinue, vars);
      }
      debugPrint(
        '[Orchestrator p$projectId] task ${task.task_pk}: functional verify hit turn cap without a verdict.',
      );
    } finally {
      await _releaseTaskTree(task.task_pk);
    }
  }

  /// Run a workflow/dockerfile gate on [branch] and wait for its terminal result
  /// — deterministic, NO LLM. Returns null when the build infra can't run (the
  /// caller retries without penalty); `(passed: true, runPk: null)` when there is
  /// nothing to run; otherwise the run's pass/fail and its id.
  Future<({bool passed, int? runPk})?> _runWorkflowGate({
    required int clientPk,
    required String branch,
    String? workflowPath,
    String? dockerfilePath,
    String? imageTag,
    required String triggeredBy,
  }) async {
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final build = handles.build;
    if (ws == null || build == null) return null;
    int runPk;
    try {
      if (workflowPath != null && workflowPath.isNotEmpty) {
        runPk = (await build.startWorkflowRun(
          clientPk: clientPk,
          projectPk: projectId,
          ws: ws,
          workflowPath: workflowPath,
          branch: branch,
          triggeredBy: triggeredBy,
        )).runPk;
      } else if (dockerfilePath != null && dockerfilePath.isNotEmpty) {
        final tag = (imageTag != null && imageTag.isNotEmpty)
            ? imageTag
            : 'gate-${branch.replaceAll('/', '-')}:latest';
        runPk = (await build.startDockerBuild(
          clientPk: clientPk,
          projectPk: projectId,
          ws: ws,
          dockerfilePath: dockerfilePath,
          imageTag: tag,
          branch: branch,
          triggeredBy: triggeredBy,
        )).runPk;
      } else {
        return (passed: true, runPk: null);
      }
    } catch (e) {
      debugPrint(
        '[Orchestrator p$projectId] gate failed to start on "$branch": $e',
      );
      return (passed: false, runPk: null);
    }
    final deadline = DateTime.now().add(_buildTimeout);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_buildPollInterval);
      final run = await _db.getCiRun(runPk);
      if (run == null) break;
      final status = CiStatusX.fromWire(run.status);
      if (status.isTerminal) {
        return (passed: status == CiStatus.success, runPk: runPk);
      }
    }
    return (passed: false, runPk: runPk); // timed out → fail the gate
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

  /// Like [_collectBuildErrors] but for the TESTING phase: returns EVERY failpoint
  /// (not just a 4k tail) plus a COUNT, so the fixer can address them ALL in one
  /// pass and the phase can track progress run-over-run. The count excludes the
  /// "N issues found" summary line so it reflects actual failures.
  Future<({String text, int count})> _collectCiFailpoints(int runPk) async {
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
    // Count = diagnostic lines that are real failpoints (drop the "N issues
    // found" / summary lines so the progress metric tracks failures, not totals).
    final summaryRe = RegExp(r'\bissues?\s+found\b', caseSensitive: false);
    final failpoints = hits.where((l) => !summaryRe.hasMatch(l)).toList();
    final picked = failpoints.isNotEmpty
        ? failpoints
        : (hits.isNotEmpty
              ? hits
              : lines.reversed.take(60).toList().reversed.toList());
    var text = picked.join('\n').trim();
    // Generous cap (keep the HEAD so the first failures, usually the root cause,
    // survive) — big enough that ~100 failpoints all reach the fixer in one pass.
    if (text.length > _maxFixErrorChars) {
      text =
          '${text.substring(0, _maxFixErrorChars)}\n… (additional failures truncated — fix these first, the rest surface on the next run)';
    }
    return (text: text, count: picked.length);
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
        }, timeout: _laneOpTimeout);
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
      } on TimeoutException catch (e) {
        // The lane op hung (NOT a conflict) — the lane has now self-healed for
        // the next waiter. Don't drag in a Coordinator to "resolve" a conflict
        // that doesn't exist; un-count the attempt and leave the task built/
        // verified so the merge pool retries it cleanly next pump.
        debugPrint(
          '[Orchestrator p$projectId] task ${task.task_pk}: auto-merge timed out ($e) — yielding back for retry.',
        );
        _undoAttempt(task.task_pk);
        return;
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
    final resolved = await _resolveBackend(persona, taskPk: task.task_pk);
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
        await for (final _ in session.runTurn(kickoff).timeout(_turnIdleTimeout)) {}
      } catch (e) {
        if (e is TimeoutException || _isNotTaskFault(e)) {
          _undoAttempt(task.task_pk); // stall/backpressure/transient — don't penalize
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
        // Templating is done — the gate is open; pass silently (this runs on
        // every pump, so logging here spams once-per-cycle forever).
        return true;
      case 'failed':
        return false; // surfaced; a human re-runs templating to retry
      default: // 'pending' | 'scaffolding'
        if (_templating) return false;
        _templating = true;
        // ignore: avoid_print
        print('[Templater] gate open → kicking off templating for project '
            '$projectId (status="${project.templateStatus}")');
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
      // ignore: avoid_print
      print('[Templater] phase started (scaffolding) for project $projectId');
      final scaffolded = await _runTemplaterAgent(project);
      // ignore: avoid_print
      print('[Templater] scaffolder returned: $scaffolded');
      if (!scaffolded) {
        await _db.setProjectTemplateStatus(projectId, 'failed');
        debugPrint('[Orchestrator p$projectId] templater could not scaffold; gated.');
        return;
      }
      // Guarantee a deterministic CI gate exists so per-task review and the
      // end-of-project scan always have a fast, no-LLM build to run.
      await _ensureDefaultCiWorkflow(project);
      // The base CI gate is a BEST-EFFORT sanity check, NOT a blocker. A stub
      // scaffold legitimately can't pass `flutter test` yet (nothing is built),
      // and a slow/missing runner shouldn't strand the whole project before any
      // task starts. So run it for the log, but ALWAYS open the gate — the
      // end-of-project CI scan is the real test gate (the "test at the end"
      // design). Templating only ends in `failed` when the SCAFFOLD itself
      // couldn't be produced (handled above / in the catch).
      final ciOk = await _runBaseCiGate(project);
      await _db.setProjectTemplateStatus(projectId, 'ready');
      debugPrint(
        '[Orchestrator p$projectId] templating done → ready'
        '${ciOk ? '' : ' (base CI was red/unrunnable — proceeding; end-of-project scan is the real gate)'}.',
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
    // Scaffolding is a CODING job — prefer a generalist worker (its model is
    // code-tuned), not the Coordinator (whose model is the interview/discovery
    // collection, which just chats instead of creating files). Fall back to the
    // Coordinator only if no worker persona exists.
    final persona = await _findPersonaForRole(AgentRole.sdeGeneralist) ??
        await _findPersonaForRole(AgentRole.coordinator);
    if (persona == null) {
      // ignore: avoid_print
      print('[Templater] NO generalist/Coordinator persona — cannot scaffold (failed/gated).');
      return false;
    }
    final resolved = await _resolveBackend(persona);
    if (resolved == null) {
      // ignore: avoid_print
      print('[Templater] no inference backend for ${persona.name} — cannot scaffold.');
      return false;
    }
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final git = handles.git;
    if (ws == null || git == null) {
      // ignore: avoid_print
      print('[Templater] workspace/git unavailable — cannot scaffold.');
      return false;
    }

    // Scaffold onto main so every task branch (created off it) inherits the base.
    try {
      await git.checkoutBranch('main');
    } catch (_) {
      // No main yet — the scaffolder's first commit creates it.
    }
    // RETRY-SAFE: if main already carries a real scaffold (e.g. this is a retry
    // after a later step failed), don't re-run the agent — it would create no new
    // commit (the files exist) and look like a failure. Reuse the scaffold and
    // let the caller proceed (re-run the CI gate, etc.).
    final existingHead = await git.headOid();
    if (existingHead != null) {
      final existingFiles =
          (await ws.walk()).where((f) => !f.isDirectory).length;
      if (existingFiles > 0) {
        // ignore: avoid_print
        print('[Templater] scaffold already present (head=$existingHead, '
            '$existingFiles file(s)) — skipping re-scaffold.');
        return true;
      }
    }
    // A pre-existing main commit must NOT let the templater "succeed" without
    // doing work, so we only count it scaffolded once a NEW commit lands.
    final beforeHead = await git.headOid();
    // ignore: avoid_print
    print('[Templater] running scaffolder agent "${persona.name}" on main '
        '(beforeHead=${beforeHead ?? "unborn"}).');

    final tasks = await _db.getTasksForProject(projectId);
    final taskList = tasks.map((t) => '- ${t.title}').join('\n');
    final baseSpec = await _buildTemplaterBaseSpec();
    final prompts = await _loadPrompts();
    final vars = PromptVars(
      taskId: 0,
      title: project.name,
      branch: 'main',
      taskList: taskList,
      baseSpec: baseSpec,
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
      // Scaffold-only toolset: file/git/CI only — no image/story/task tools, so
      // the scaffolder can't wander off (e.g. into image generation).
      scaffoldMode: true,
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
      var toolCalls = 0;
      try {
        await for (final _ in session.runTurn(
          kickoff,
          onToolResult: (r) {
            toolCalls++;
            // ignore: avoid_print
            print('[Templater] tool#$toolCalls: '
                '${r.length > 140 ? "${r.substring(0, 140)}…" : r}');
          },
        ).timeout(_turnIdleTimeout)) {}
      } catch (e) {
        if (e is! TimeoutException && !_isNotTaskFault(e)) {
          debugPrint('[Orchestrator p$projectId] templater turn $turn failed: $e');
          return (await git.headOid()) != beforeHead;
        }
        // stall/transient/backpressure — retry the turn.
      }
      final head = await git.headOid();
      final wsFiles =
          (await ws.walk()).where((f) => !f.isDirectory).length;
      // ignore: avoid_print
      print('[Templater] turn $turn: $toolCalls tool call(s); '
          'workspace has $wsFiles file(s); head=${head ?? "unborn"} '
          '(beforeHead=${beforeHead ?? "unborn"}).');
      if (head != beforeHead && wsFiles > 0) {
        // ignore: avoid_print
        print('[Templater] NEW commit + $wsFiles file(s) — scaffold accepted.');
        // Make the scaffold visible in the Code & Git workspace view right away.
        ref.read(workspaceRevisionProvider(projectId).notifier).state++;
        return true;
      }
      kickoff =
          'You have NOT produced a real scaffold yet (workspace shows $wsFiles '
          'file(s)). Use create_file to write the manifest + main runner + a stub '
          'file per task (+ DB schema if there is a database), THEN git_commit. '
          'An empty commit does not count.';
    }
    // ignore: avoid_print
    print('[Templater] hit turn cap without a real scaffold — FAILED.');
    return false; // the loop returns true only on a real (file-bearing) commit
  }

  /// The Templater's base spec: the condensed top-of-tree story (a whole-project
  /// overview the scaffold is built from) plus a database-schema instruction when
  /// the project's stack includes a database. Empty when neither applies.
  Future<String> _buildTemplaterBaseSpec() async {
    final buf = StringBuffer();
    try {
      final stories = await _db.getUserStoriesForProject(projectId);
      final roots = stories.where((s) => s.parent_story_fk == null).toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      if (roots.isNotEmpty) {
        final root = roots.first;
        buf.writeln(
          'PROJECT OVERVIEW (the top of the story tree — a condensed view of the '
          'WHOLE project; scaffold the base so it fits this end to end):',
        );
        buf.writeln('- ${root.title}');
        final narrative = root.narrative.trim();
        if (narrative.isNotEmpty) buf.writeln('  $narrative');
        final ac = (root.acceptanceCriteria ?? '').trim();
        if (ac.isNotEmpty) buf.writeln('  Acceptance: $ac');
      }
      // Database in the stack → seed a consistent starter schema in the base so
      // every later task shares one data model.
      final tags = await _db.getTagsForProject(projectId);
      final hasDb = tags.any(
        (t) => t.category == 'databases' && t.status != 'rejected',
      );
      if (hasDb) {
        if (buf.isNotEmpty) buf.writeln();
        buf.writeln(
          'DATABASE: this project uses a database (see the BASELINE). Create a '
          'basic STARTER SCHEMA — the core tables/entities the overview implies — '
          'as a real migration/schema file for the chosen DB, so every task '
          'builds on one consistent data model. Keep it minimal but coherent.',
        );
      }
    } catch (e) {
      debugPrint('[Orchestrator p$projectId] templater base-spec build failed: $e');
    }
    return buf.toString().trim();
  }

  /// Run the project's CI once against main as the base gate: the first
  /// task-configured workflow/dockerfile, else the default CI workflow scaffolded
  /// by [_ensureDefaultCiWorkflow]. Returns true on green / nothing-to-run, false
  /// on a red run (infra-down does NOT block templating).
  Future<bool> _runBaseCiGate(Project project) async {
    final tasks = await _db.getTasksForProject(projectId);
    String? workflowPath;
    String? dockerfilePath;
    for (final t in tasks) {
      final wf = t.workflowPath?.trim() ?? '';
      final df = t.dockerfilePath?.trim() ?? '';
      if (wf.isNotEmpty || df.isNotEmpty) {
        workflowPath = wf.isNotEmpty ? wf : null;
        dockerfilePath = df.isNotEmpty ? df : null;
        break;
      }
    }
    if (workflowPath == null && dockerfilePath == null) {
      // Fall back to the default CI workflow if one was scaffolded.
      final ws = (await _resolveWorkspaceHandles()).ws;
      if (ws != null && await ws.exists(_defaultCiPath)) {
        workflowPath = _defaultCiPath;
      } else {
        return true; // nothing to run → the compiling scaffold is the bar
      }
    }
    final outcome = await _runWorkflowGate(
      clientPk: project.client_fk,
      branch: 'main',
      workflowPath: workflowPath,
      dockerfilePath: dockerfilePath,
      imageTag: 'base:latest',
      triggeredBy: 'templater',
    );
    return outcome?.passed ?? true; // infra unavailable → don't block templating
  }

  /// Guarantee the project has ONE deterministic CI workflow at [_defaultCiPath]
  /// on main, so per-task review and the end-of-project scan always have a fast,
  /// no-LLM gate to run. Idempotent (no-op if the Templater already wrote one).
  /// Written + committed deterministically — no agent — so it can't be skipped or
  /// hallucinated.
  Future<void> _ensureDefaultCiWorkflow(Project project) async {
    try {
      final handles = await _resolveWorkspaceHandles();
      final ws = handles.ws;
      final git = handles.git;
      if (ws == null || git == null) return;
      if (await ws.exists(_defaultCiPath)) return;
      final kind = await _detectStackKind();
      final yaml = _defaultCiYaml(kind);
      final lane = ref.read(gitLaneProvider(projectId));
      await lane.run(() async {
        try {
          await git.checkoutBranch('main');
        } catch (_) {
          // Unborn main — the scaffolder's commit will have created it by now;
          // if not, commitAll roots the first commit.
        }
        await ws.writeString(_defaultCiPath, yaml);
        await git.commitAll(message: 'ci: add default $kind CI gate');
      }, timeout: _laneOpTimeout);
      ref.read(workspaceRevisionProvider(projectId).notifier).state++;
      debugPrint(
        '[Orchestrator p$projectId] wrote default CI gate ($kind) at $_defaultCiPath.',
      );
    } catch (e) {
      debugPrint(
        '[Orchestrator p$projectId] could not ensure default CI gate: $e',
      );
    }
  }

  /// Pick the CI workflow flavor from the project's chosen stack (tags). Drives
  /// which `run:` steps the local runner executes for the compile/analyze gate.
  Future<String> _detectStackKind() async {
    try {
      final tags = await _db.getTagsForProject(projectId);
      final stack = tags
          .where((t) => t.status != 'rejected')
          .map((t) => '${t.category}:${t.value}'.toLowerCase())
          .join(' ');
      bool has(List<String> needles) => needles.any(stack.contains);
      if (has(['flutter'])) return 'flutter';
      if (has(['dart'])) return 'dart';
      if (has(['c#', 'csharp', '.net', 'dotnet', 'asp.net'])) return 'dotnet';
      if (has(['node', 'javascript', 'typescript', 'react', 'next', 'vue', 'angular', 'express'])) {
        return 'node';
      }
      if (has(['python', 'django', 'flask', 'fastapi'])) return 'python';
      if (has(['golang', ' go ', ':go'])) return 'go';
      if (has(['rust', 'cargo'])) return 'rust';
    } catch (_) {}
    return 'generic';
  }

  /// The default GitHub-Actions-format CI body for [kind]. The local runner runs
  /// `run:` steps as shell commands (`uses:` steps are recorded but skipped), so
  /// these are the conventional compile/analyze/test commands for each stack.
  static String _defaultCiYaml(String kind) {
    final steps = switch (kind) {
      'flutter' => '      - run: flutter pub get\n'
          '      - run: flutter analyze\n'
          '      - run: flutter test',
      'dart' => '      - run: dart pub get\n'
          '      - run: dart analyze\n'
          '      - run: dart test',
      'dotnet' => '      - run: dotnet restore\n'
          '      - run: dotnet build --no-restore\n'
          '      - run: dotnet test --no-build',
      'node' => '      - run: npm ci\n'
          '      - run: npm run build --if-present\n'
          '      - run: npm test --if-present',
      'python' => '      - run: pip install -r requirements.txt\n'
          '      - run: python -m pytest',
      'go' => '      - run: go build ./...\n'
          '      - run: go test ./...',
      'rust' => '      - run: cargo build\n'
          '      - run: cargo test',
      _ => '      - run: echo "No build configured for this stack"',
    };
    return 'name: CI\n'
        'on: [push, pull_request]\n'
        'jobs:\n'
        '  build:\n'
        '    runs-on: ubuntu-latest\n'
        '    steps:\n'
        '$steps\n';
  }

  /// Open the next milestone batch when appropriate. Two triggers:
  ///   1. The current-or-earlier batches are fully finished (clean progression).
  ///   2. BACKFILL: there are IDLE worker slots and the current batch has no more
  ///      STARTABLE work — its remaining tasks are all in flight (or held) — so
  ///      the next batch opens to feed the idle slots instead of the pipeline
  ///      tailing off to a single task while later batches sit gated. This is what
  ///      keeps all N connections busy across a batch boundary (the "11 & 12
  ///      finished but the next 25 never started" stall).
  /// Advances at most ONE batch per call; since each stage re-pumps on completion,
  /// it opens just enough batches to keep the workers fed. A Blocked task is
  /// surfaced to the human and does NOT freeze progression. No-op on the last batch.
  Future<bool> _maybeAdvanceMilestone(Project project, int workerCap) async {
    final count = project.milestoneCount;
    if (count <= 1) return false;
    final current = project.currentMilestone;
    if (current >= count - 1) return false;
    final tasks = await _db.getTasksForProject(projectId);
    final inScope = tasks.where((t) => (t.milestoneOrder ?? 0) <= current);
    if (inScope.isEmpty) return false;
    final batchDone = !inScope.any(
      (t) => t.status != TaskStatus.done && t.status != TaskStatus.blocked,
    );
    // Idle slots + nothing startable in the current scope → backfill from next.
    final idleSlots = _active.length < workerCap;
    final noStartable = _assignableTasks(tasks, current).isEmpty;
    if (!batchDone && !(idleSlots && noStartable)) return false;
    final next = await _db.advanceProjectMilestone(projectId);
    debugPrint(
      '[Orchestrator p$projectId] milestone $current → opening $next/${count - 1} '
      '(${batchDone ? 'batch complete' : 'backfilling idle worker slots'}).',
    );
    return true;
  }

  /// END-OF-PROJECT CI SCAN — the hard gate on "complete". Once the whole backlog
  /// is Done (final milestone, nothing open) we run the project's CI gate ONCE
  /// against main:
  ///   • GREEN → the project is genuinely complete; nothing to do.
  ///   • RED → reopen the most-recently-finished task with the FULL diagnostics
  ///     attached, so the failure is fixed before the project can be counted
  ///     complete (the board is no longer empty, so it isn't "done"). The task's
  ///     retry budget eventually surfaces it as Blocked if it can't be made green.
  /// Per-task review already gated each branch, but the post-merge integration on
  /// main can still surface issues no single branch saw — this is that net.
  /// Returns true when it spawned new assignable work (a fix-phase batch), so
  /// the caller can re-pump immediately to fill idle slots instead of waiting
  /// for the next tick.
  Future<bool> _maybeFinalizeProject(Project project) async {
    if (_testing) return false; // a TESTING phase is already running
    // Only when the project is on its last milestone batch.
    if (project.currentMilestone < project.milestoneCount - 1) return false;
    final tasks = await _db.getTasksForProject(projectId);
    if (tasks.isEmpty) return false;
    final open = tasks.where(
      (t) =>
          t.status == TaskStatus.todo ||
          t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.review,
    );
    if (open.isNotEmpty) return false; // work still in flight — not finished yet
    final done = tasks.where((t) => t.status == TaskStatus.done).toList();
    if (done.isEmpty) return false; // nothing built (all blocked) — leave it
    // Skip if this exact completed state already passed (or exhausted) testing —
    // don't re-run the slow loop every tick on a settled project.
    final sig = '${done.length}:'
        '${done.map((t) => t.updatedAt.millisecondsSinceEpoch).fold<int>(0, (a, b) => a > b ? a : b)}';
    if (sig == _finalScanPassedSig || sig == _testingExhaustedSig) return false;
    // Need a gate to scan against; if none exists there's nothing to enforce.
    final ws = (await _resolveWorkspaceHandles()).ws;
    if (ws == null || !await ws.exists(_defaultCiPath)) return false;

    // Enter the dedicated TESTING phase (mirrors the templating gate): run it in
    // the background and re-pump when it lands, so the pump never blocks on the
    // slow scan/fix loop.
    _testing = true;
    unawaited(
      _runTestingPhase(project, sig).whenComplete(() {
        _testing = false;
        if (!_disposed) unawaited(_pump());
      }),
    );
    return false;
  }

  /// The TESTING phase: a dedicated end-of-project stage (like the yellow
  /// Templating stage — NOT a task) that repeatedly runs CI on main and, on RED,
  /// drives ONE focused fix agent (the strongest model, handed ALL the failpoints
  /// at once) to fix the whole project before the next run, then re-scans. Keeps
  /// looping while it's making PROGRESS (fewer failpoints each run); only gives up
  /// after the count fails to drop for [_maxStagnantRounds] rounds. [doneSig] is
  /// the completed-task signature this run gates, so a pass/exhaust suppresses
  /// re-running for the same settled state.
  Future<void> _runTestingPhase(Project project, String doneSig) async {
    _setTesting(true, 'Testing — running CI on main…');
    try {
      var stagnant = 0;
      int? prevCount;
      for (var round = 1; round <= _absoluteMaxTestingRounds; round++) {
        if (!await _stillRunning()) return;
        _setTesting(true, 'Testing — CI run $round…');
        debugPrint(
          '[Orchestrator p$projectId] TESTING phase round $round: running CI on '
          'main (this can take a few minutes)…',
        );
        final outcome = await _runWorkflowGate(
          clientPk: project.client_fk,
          branch: 'main',
          workflowPath: _defaultCiPath,
          triggeredBy: 'testing',
        );
        if (outcome == null) return; // infra down — retry on a later pump/tick
        if (outcome.passed) {
          _finalScanPassedSig = doneSig; // settled green — stop re-scanning
          // SUCCESS CONDITION: mark the project complete so the pump stops and
          // the UI shows a clear "complete" state (not just a silent idle).
          await _db.setProjectOrchestrationState(projectId, 'completed');
          debugPrint(
            '[Orchestrator p$projectId] TESTING phase GREEN at round $round — '
            'project COMPLETE (CI passing on main).',
          );
          return;
        }

        // Count this run's failpoints and gather ALL of them for the fixer (so it
        // fixes everything in one pass, not one error per CI run).
        final diag = outcome.runPk != null
            ? await _collectCiFailpoints(outcome.runPk!)
            : (text: '', count: 0);
        debugPrint(
          '[Orchestrator p$projectId] TESTING phase round $round: CI RED — '
          '${diag.count} failpoint(s)'
          '${prevCount != null ? ' (was $prevCount)' : ''}.',
        );

        // PROGRESS GATE: keep going as long as the failure count is dropping;
        // only count a NON-improving run toward the stagnation budget. This lets
        // it grind a big backlog (e.g. 100 → 60 → 25 → 0) without the user
        // stepping in, while still bailing if it's truly stuck.
        if (prevCount != null && diag.count >= prevCount) {
          stagnant++;
          if (stagnant >= _maxStagnantRounds) {
            _testingExhaustedSig = doneSig;
            debugPrint(
              '[Orchestrator p$projectId] TESTING phase: failpoint count hasn\'t '
              'dropped for $_maxStagnantRounds rounds (${diag.count} left) — '
              'leaving for manual review.',
            );
            return;
          }
        } else {
          stagnant = 0; // made progress this round
        }
        prevCount = diag.count;

        _setTesting(
          true,
          'Testing — fixing ${diag.count} error(s) (round $round)…',
        );
        await _runFixAgent(project, diag.text, round);
      }
      // Hard backstop hit (should be rare — progress gate usually ends it first).
      _testingExhaustedSig = doneSig;
      debugPrint(
        '[Orchestrator p$projectId] TESTING phase hit the $_absoluteMaxTestingRounds-'
        'round backstop — CI still RED; leaving for manual review.',
      );
    } catch (e, st) {
      debugPrint('[Orchestrator p$projectId] TESTING phase errored: $e\n$st');
    } finally {
      _setTesting(false, null);
    }
  }

  /// Drive ONE focused fix agent over the WHOLE project on main: hand it ALL the
  /// CI errors at once and let it read/edit/commit across as many files as it
  /// needs (this is the "fix the project", not "fix one file" job). Uses the
  /// generalist's code-tuned model — on the routed plan that's the full default
  /// Omni collection (the strongest available). Returns true if it landed a new
  /// commit (so the next CI scan sees the changes).
  Future<bool> _runFixAgent(Project project, String errors, int round) async {
    final persona = await _findPersonaForRole(AgentRole.sdeGeneralist) ??
        await _findPersonaForRole(AgentRole.coordinator);
    if (persona == null) return false;
    final resolved = await _resolveBackend(persona);
    if (resolved == null) return false;
    final handles = await _resolveWorkspaceHandles();
    final ws = handles.ws;
    final git = handles.git;
    if (ws == null || git == null) return false;

    // The fixer works directly on main (the backlog is drained, so nothing else
    // is touching it). Its commits are what the next CI scan reads.
    try {
      await git.checkoutBranch('main');
    } catch (_) {}
    final beforeHead = await git.headOid();

    final baseline = await buildProjectBaseline(_db, projectId);
    final fileTree = (await ws.walk())
        .where((f) => !f.isDirectory)
        .map((f) => f.path)
        .toList()
      ..sort();
    final filesBlock = fileTree.take(300).join('\n');
    final systemPrompt = StringBuffer()
      ..writeln(baseline)
      ..writeln()
      ..writeln(defaultSystemPrompt(AgentRole.sdeGeneralist))
      ..writeln()
      ..writeln(
        'You are the end-of-project TESTING & FIX agent. The whole project is '
        'built and merged onto main, but its CI build/tests are FAILING. Your '
        'job is to make the WHOLE project compile cleanly and its tests pass.',
      )
      ..writeln(
        '- Work across AS MANY FILES AS NEEDED — read the failing files, find '
        'the real cause, and fix it. Do not stop at the first error; resolve the '
        'whole class of failures.',
      )
      ..writeln(
        '- Keep changes minimal and correct; do not delete features or stub '
        'things out to silence errors. Preserve existing behavior.',
      )
      ..writeln(
        '- ALWAYS read_file the EXACT current contents of a file immediately '
        'before you edit_file it, and copy old_text VERBATIM (exact whitespace, '
        'indentation, and punctuation) from what you just read — never from '
        'memory or a guess. If old_text "was not found", re-read the file and try '
        'again; for a large or uncertain change, use write_file to replace the '
        'whole file instead of edit_file.',
      )
      ..writeln(
        '- When you have applied your fixes, git_commit them (an uncommitted '
        'change does not count — CI only sees committed work). Do NOT run the CI '
        'workflow yourself; the phase re-runs it for you after you commit.',
      )
      ..writeln()
      ..writeln('=== CURRENT PROJECT FILES (on main) ===')
      ..writeln(filesBlock);

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
      // File/git ONLY toolset — read/edit/write/commit. No CI/build tools (the
      // phase re-runs CI itself, and the generalist persona denies them, so
      // offering them only tempts a blocked call), no task/story/image tools.
      fixMode: true,
      systemPromptOverride: systemPrompt.toString(),
      enableThinking: resolveEnableThinking(
        agent: personaThinkingMode(persona.configJson, personaName: persona.name),
        task: ThinkingMode.off,
      ),
    );

    var kickoff =
        'CI on main is RED with the failpoints below. Fix EVERY one of them in '
        'this session — work through the WHOLE list, committing as you finish each '
        'file or group. Do NOT stop after the first fix and do NOT ask to re-run '
        'CI: keep going until every listed failure is addressed (the phase re-runs '
        'CI for you afterwards). Failpoints:\n\n$errors';
    // Work through ALL failpoints in one pass — do NOT bail on the first commit
    // (that's what made it "test after every point"). But the "done" signal is the
    // agent no longer making CHANGES, not no longer using tools: it'll keep
    // reading/searching the whole tree forever otherwise (observed: 1 failpoint
    // fixed by turn 3, still re-scanning at turn 10+). So break once it goes a
    // couple of turns EDITING nothing — then the outer loop re-runs CI once and
    // tackles whatever's left (including any NEW failures the fixes uncovered).
    var idleTurns = 0;
    var noEditTurns = 0;
    for (var turn = 0; turn < _maxFixAgentTurns && !_disposed; turn++) {
      if (!await _stillRunning()) break;
      var sawTool = false;
      var sawEdit = false;
      var transient = false;
      try {
        await for (final _ in session.runTurn(
          kickoff,
          maxToolRounds: 8,
          onToolResult: (r) {
            sawTool = true;
            // Did this tool result actually CHANGE the tree (edit/write/commit/
            // move/create)? Reads & searches don't count toward "still working".
            final rl = r.toLowerCase();
            if (rl.contains('edited "') ||
                rl.contains('committed all changes') ||
                rl.contains('committed your working tree') ||
                rl.contains('updated file') ||
                rl.contains('created file') ||
                rl.contains('wrote ') ||
                rl.contains('moved ')) {
              sawEdit = true;
            }
            debugPrint(
              '[Orchestrator p$projectId] testing-fix r$round turn $turn tool → '
              '${r.length > 140 ? '${r.substring(0, 140)}…' : r}',
            );
          },
        ).timeout(_turnIdleTimeout)) {}
      } catch (e) {
        if (e is! TimeoutException && !_isNotTaskFault(e)) {
          debugPrint(
            '[Orchestrator p$projectId] testing-fix turn $turn failed: $e',
          );
          break;
        }
        transient = true; // stall / backpressure / transient — retry the turn.
      }
      // Keep the Code & Git view fresh as commits land.
      if (!_disposed) {
        ref.read(workspaceRevisionProvider(projectId).notifier).state++;
      }
      if (transient) continue; // don't count a failed turn as "idle/done"
      if (!sawTool) {
        // A turn with no tool calls = the agent thinks it's finished. Give it one
        // nudge in case it stopped early, then accept it's done.
        idleTurns++;
        if (idleTurns >= 2) break;
        kickoff =
            'If EVERY failpoint above is now fixed AND committed, reply "done". '
            'Otherwise keep fixing the remaining ones and git_commit them.';
        continue;
      }
      idleTurns = 0;
      if (sawEdit) {
        noEditTurns = 0;
        kickoff =
            'Keep going — fix the REMAINING failpoints from the list and '
            'git_commit them. Re-read each file right before editing. When ALL '
            'are fixed and committed, reply "done".';
      } else {
        // Tools ran but nothing changed (just reading/searching). After a couple
        // of these the agent is done fixing — stop and let CI re-run rather than
        // re-scanning the whole project.
        noEditTurns++;
        if (noEditTurns >= 2) break;
        kickoff =
            'You made no code change that turn. If every failpoint is fixed and '
            'committed, reply "done" and stop. If something still needs fixing, '
            'edit it and git_commit now — do NOT keep re-reading files.';
      }
    }
    // SAFETY COMMIT: the next CI run only sees COMMITTED work, so if the agent
    // left edits uncommitted, commit them now rather than losing the pass.
    try {
      if (!(await git.status()).isClean) {
        final lane = ref.read(gitLaneProvider(projectId));
        await lane.run(
          () => git.commitAll(
            message: 'testing: auto-commit pending fixes (round $round)',
          ),
          timeout: _laneOpTimeout,
        );
        debugPrint(
          '[Orchestrator p$projectId] testing-fix r$round: safety-committed '
          'leftover uncommitted fixes.',
        );
      }
    } catch (e) {
      debugPrint(
        '[Orchestrator p$projectId] testing-fix r$round: safety commit skipped ($e).',
      );
    }
    return (await git.headOid()) != beforeHead;
  }

  /// Update the live TESTING phase flag/detail and mirror it into
  /// [orchestratorStatusProvider] so the top-bar shows a yellow "Testing" stage.
  void _setTesting(bool active, String? detail) {
    _testingActive = active;
    _testingDetail = detail;
    if (_disposed) return;
    try {
      final cur = ref.read(orchestratorStatusProvider(projectId));
      ref.read(orchestratorStatusProvider(projectId).notifier).state =
          OrchestratorStatus(
            workerSlots: cur.workerSlots,
            activeStages: cur.activeStages,
            waiting: cur.waiting,
            testing: active,
            testingDetail: detail,
          );
    } catch (_) {}
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
    if (_disposed) return (ws: null, git: null, build: null);
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
    if (_disposed) return null;
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
    // The orchestrator provider can be DISPOSED (project unfocused / view
    // unmounted) while this stage is still in flight; touching `ref` then throws
    // "Cannot use Ref after it has been disposed". Skip the provider invalidate
    // in that case — just clean the scratch disk (the committed work is safe on
    // the task branch). Guarded + caught so cleanup can never crash a stage.
    if (!_disposed) {
      try {
        ref.invalidate(
          taskWorkspaceProvider((projectId: projectId, taskPk: taskPk)),
        );
      } catch (_) {}
    }
    try {
      await deleteTaskDisk(projectId, taskPk);
    } catch (_) {}
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

  /// True if the shared HTTP client was closed out from under an in-flight
  /// request — this happens when the project is unfocused mid-turn
  /// (`resetInferenceConnections`). It is NOT the task's fault: the task yields
  /// and the next pump re-dispatches it against a freshly-created client.
  static bool _isClosedClient(Object e) =>
      e is LemonadeApiException &&
      e.message.toLowerCase().contains('client is already closed');

  /// True if the stream dropped mid-flight — a transient network/connection error
  /// (the router or the socket closed the connection while data was streaming),
  /// NOT a model/task fault. Seen as `http.ClientException: Connection closed
  /// while receiving data` and similar. Without classifying these as transient, a
  /// single flaky stream killed the whole turn (the Testing fix agent broke on
  /// turn 0 and never retried → no progress → the phase gave up). These should be
  /// retried, exactly like a 502/429.
  static bool _isTransientNetwork(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('connection terminated') ||
        s.contains('connection refused') ||
        s.contains('connection attempt failed') ||
        s.contains('software caused connection abort') ||
        s.contains('socketexception') ||
        s.contains('handshakeexception') ||
        s.contains('httpexception') ||
        (s.contains('clientexception') && s.contains('connection'));
  }

  /// Backpressure (429), a transient 5xx, a client closed by a project swap, or a
  /// dropped stream — none should count as a failed attempt against the task.
  bool _isNotTaskFault(Object e) =>
      _isConnCap(e) ||
      _isTransientServer(e) ||
      _isClosedClient(e) ||
      _isTransientNetwork(e);

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
    AgentPersona persona, {
    int? taskPk,
  }) async {
    if (_disposed) return null;
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
    // Router serves the Omni COLLECTION id (kDefaultOmniCollection) DIRECTLY, so
    // send it as-is and default to it — never decompose to a raw sub-model, which
    // fell through to a small 4B (e.g. Qwen3.5-4B): the wrong model, and (when the
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
    var model = routed
        ? ((pLlm != null && pLlm.trim().isNotEmpty) ? pLlm.trim() : collection)
        : resolveAgentChatModel(
            routed: false,
            personaModel: pLlm,
            selectedModel: chosen.selectedModel,
            serverModels: serverModels,
          );
    // SELF-HEAL a server-side collection rename: if the routed server advertises a
    // model list and it doesn't include the id we're about to send, swap to an
    // advertised chat/omni collection so a stale persona id can't strand the run.
    if (routed && models.isNotEmpty && !models.contains(model)) {
      final alt = pickRoutedCollectionId(models);
      if (alt != null && alt != model) {
        debugPrint(
          '[Orchestrator p$projectId] routed collection "$model" not advertised '
          '— self-healing to "$alt".',
        );
        model = alt;
      }
    }
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
    // Routing session id → the Router pins a session to ONE warm backend and
    // spreads DIFFERENT sessions across the fleet. For concurrent autonomous work
    // we key the session by TASK (not just agent) so several tasks of the SAME
    // persona (e.g. the Generalist doing most of the coding) fan out across
    // backends instead of all piling onto one box — otherwise only ~2 of N worker
    // slots ever get a live connection. A task's own turns reuse its id, so each
    // task still stays warm on its backend. No taskPk (e.g. the one-shot
    // Templater) falls back to the per-agent id.
    final sessionId = taskPk != null
        ? 'agent-${persona.agent_pk}-task-$taskPk'
        : 'agent-${persona.agent_pk}';
    return (
      client: backendForServer(
        uiServer,
        agentName: persona.name,
        sessionId: sessionId,
      ),
      model: model,
    );
  }
}

/// The pipeline stage a task is ready for, in execution order.
enum _Stage { implement, verify, build, merge }

/// A live snapshot of the orchestrator's worker-slot usage, published every pump
/// so the UI can explain an idle slot — e.g. a task held back because its files
/// overlap work in flight — instead of just showing fewer agents than the plan
/// allows.
@immutable
class OrchestratorStatus {
  /// Worker pool size = concurrency cap minus the reserved Coordinator slot.
  final int workerSlots;

  /// Tasks in an active pipeline stage right now (implement/verify/build/merge).
  final int activeStages;

  /// One entry per startable-but-blocked task (file-scope holds): its task pk,
  /// the agent assigned to it, and a human-readable reason.
  final List<OrchestratorWait> waiting;

  /// True while the end-of-project TESTING phase is running (CI scan + focused
  /// fix loop). The UI shows a yellow "Testing" stage, like Templating.
  final bool testing;

  /// Human-readable detail for the TESTING phase (e.g. "CI run 2 of 6…").
  final String? testingDetail;

  const OrchestratorStatus({
    this.workerSlots = 0,
    this.activeStages = 0,
    this.waiting = const [],
    this.testing = false,
    this.testingDetail,
  });
}

/// A single held/waiting task in [OrchestratorStatus] — surfaced so the UI can
/// show the blocked slot (which task, which agent, why) instead of just a lower
/// agent count.
@immutable
class OrchestratorWait {
  final int taskPk;
  final int? agentFk;
  final String reason;
  const OrchestratorWait({
    required this.taskPk,
    required this.agentFk,
    required this.reason,
  });
}

/// Per-project orchestrator status the UI reads to surface held/waiting work.
final orchestratorStatusProvider =
    StateProvider.family<OrchestratorStatus, int>(
      (ref, projectId) => const OrchestratorStatus(),
    );

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
