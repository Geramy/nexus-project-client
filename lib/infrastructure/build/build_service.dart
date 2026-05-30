// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart' show Value;

import '../database/nexus_database.dart';
import '../workspace/workspace.dart';
import 'backends/local_docker_backend.dart';
import 'backends/remote_build_backend.dart';
import 'build_backend.dart';
import 'build_models.dart';
import 'ci/workflow_model.dart';
import 'ci/workflow_parser.dart';
import 'ci/workflow_runner.dart';
import 'workspace_materializer.dart';

/// A handle to a started run: its DB pk plus a [CiCancelToken] the UI/agent can
/// trip to stop it mid-flight.
class StartedRun {
  final int runPk;
  final CiCancelToken cancel;
  const StartedRun(this.runPk, this.cancel);
}

/// Orchestrates build / CI runs end-to-end: it persists the runs→jobs→steps
/// rows, materializes the project's virtual workspace to a real temp directory,
/// drives the appropriate backend (local Docker / remote) or the local workflow
/// runner, streams their log output back into the step rows, and reconciles the
/// final statuses. Callers get a [StartedRun] immediately; the work proceeds in
/// the background and the UI follows the live DB streams.
///
/// All workspace reads happen up front (during materialization) on the calling
/// isolate that owns the SQLite-backed [Workspace]; the backends then shell out
/// against the host temp dir, so no off-isolate workspace access occurs.
class BuildService {
  final NexusDatabase db;
  final WorkspaceMaterializer materializer;
  final WorkflowParser workflowParser;
  final WorkflowRunner workflowRunner;
  final LocalDockerBackend localDocker;

  /// Optional remote build server. When configured, [startDockerBuild] can be
  /// asked to run against it instead of the local Docker daemon.
  final RemoteBuildBackend? remote;

  BuildService({
    required this.db,
    this.materializer = const WorkspaceMaterializer(),
    this.workflowParser = const WorkflowParser(),
    WorkflowRunner? workflowRunner,
    LocalDockerBackend? localDocker,
    this.remote,
  })  : workflowRunner = workflowRunner ?? WorkflowRunner(),
        localDocker = localDocker ?? const LocalDockerBackend();

  BuildBackend _backendFor(CiBackendKind kind) {
    if (kind == CiBackendKind.remote && remote != null) return remote!;
    return localDocker;
  }

  /// Why the chosen backend can't run (e.g. Docker not installed), or null.
  Future<String?> backendUnavailableReason(CiBackendKind kind) =>
      _backendFor(kind).unavailableReason();

  // ── Docker build ────────────────────────────────────────────────────────

  /// Start a `docker build` of [dockerfilePath] in [ws], producing [imageTag].
  /// Persists a one-job/one-step run and streams the build log into that step.
  Future<StartedRun> startDockerBuild({
    required int clientPk,
    int? projectPk,
    required Workspace ws,
    required String dockerfilePath,
    required String imageTag,
    String buildContext = '.',
    Map<String, String> buildArgs = const {},
    CiBackendKind backend = CiBackendKind.localDocker,
    String? branch,
    String? commitOid,
    String? triggeredBy,
    int? taskPk,
  }) async {
    final name = 'docker · $imageTag';
    final runPk = await db.createCiRun(CiRunsCompanion.insert(
      client_fk: clientPk,
      project_fk: Value(projectPk),
      task_fk: Value(taskPk),
      name: name,
      status: const Value('pending'),
      kind: Value(CiRunKind.dockerBuild.wire),
      backend: Value(backend.wire),
      branch: Value(branch),
      commitOid: Value(commitOid),
      dockerfilePath: Value(dockerfilePath),
      imageTag: Value(imageTag),
      triggeredBy: Value(triggeredBy),
    ));

    final jobPk = await db.createCiJob(CiJobsCompanion.insert(
      ci_run_fk: runPk,
      name: 'build',
      orderIndex: const Value(0),
    ));
    final stepPk = await db.createCiStep(CiStepsCompanion.insert(
      ci_job_fk: jobPk,
      name: 'docker build',
      orderIndex: const Value(0),
      command: Value('docker build -t $imageTag -f $dockerfilePath $buildContext'),
    ));

    final cancel = CiCancelToken();
    // Resolve every log line (including system lines) to the single step.
    final stepPks = [
      [stepPk]
    ];
    final jobPks = [jobPk];

    unawaited(_runDockerBuild(
      runPk: runPk,
      jobPk: jobPk,
      stepPk: stepPk,
      jobPks: jobPks,
      stepPks: stepPks,
      taskPk: taskPk,
      ws: ws,
      imageTag: imageTag,
      request: CiRunRequest(
        kind: CiRunKind.dockerBuild,
        workDir: '', // filled after materialization
        dockerfilePath: dockerfilePath,
        imageTag: imageTag,
        buildContext: buildContext,
        buildArgs: buildArgs,
        branch: branch,
        commitOid: commitOid,
      ),
      backend: backend,
      cancel: cancel,
    ));

    return StartedRun(runPk, cancel);
  }

  Future<void> _runDockerBuild({
    required int runPk,
    required int jobPk,
    required int stepPk,
    required List<int> jobPks,
    required List<List<int>> stepPks,
    int? taskPk,
    required Workspace ws,
    required String imageTag,
    required CiRunRequest request,
    required CiBackendKind backend,
    required CiCancelToken cancel,
  }) async {
    MaterializedWorkspace? mat;
    final now = DateTime.now();
    try {
      await _markRunning(runPk, jobPk, stepPk);

      mat = await materializer.materialize(ws, tag: imageTag);
      final req = CiRunRequest(
        kind: request.kind,
        workDir: mat.path,
        dockerfilePath: request.dockerfilePath,
        imageTag: request.imageTag,
        buildContext: request.buildContext,
        buildArgs: request.buildArgs,
        branch: request.branch,
        commitOid: request.commitOid,
      );

      final outcome = await _backendFor(backend).execute(
        req,
        log: _logSink(stepPks),
        cancel: cancel,
      );
      await _finalize(runPk, jobPks, stepPks, outcome, startedAt: now, taskPk: taskPk);
    } catch (e) {
      await db.appendCiStepLog(stepPk, '\n[orchestrator] build failed: $e\n');
      await _failAll(runPk, jobPks, stepPks, error: '$e', taskPk: taskPk);
    } finally {
      await mat?.dispose();
    }
  }

  // ── Workflow run (local GitHub-Actions runner) ───────────────────────────

  /// Start a local run of the GitHub-Actions workflow at [workflowPath] in [ws].
  /// Parses the YAML up front to persist the jobs→steps tree, then executes it
  /// locally, streaming each step's output into its row.
  Future<StartedRun> startWorkflowRun({
    required int clientPk,
    int? projectPk,
    required Workspace ws,
    required String workflowPath,
    String? branch,
    String? commitOid,
    String? triggeredBy,
    int? taskPk,
  }) async {
    final yamlText = await ws.readString(workflowPath);
    final plan = workflowParser.parse(yamlText, fileName: _basename(workflowPath));

    final runPk = await db.createCiRun(CiRunsCompanion.insert(
      client_fk: clientPk,
      project_fk: Value(projectPk),
      task_fk: Value(taskPk),
      name: plan.name,
      status: const Value('pending'),
      kind: Value(CiRunKind.workflow.wire),
      backend: Value(CiBackendKind.localDocker.wire),
      branch: Value(branch),
      commitOid: Value(commitOid),
      workflowPath: Value(workflowPath),
      triggeredBy: Value(triggeredBy),
    ));

    // Persist the jobs→steps tree, keeping index→pk maps for log/status routing.
    final jobPks = <int>[];
    final stepPks = <List<int>>[];
    for (var j = 0; j < plan.jobs.length; j++) {
      final job = plan.jobs[j];
      final jobPk = await db.createCiJob(CiJobsCompanion.insert(
        ci_run_fk: runPk,
        name: job.name,
        runsOn: Value(job.runsOn),
        orderIndex: Value(j),
      ));
      jobPks.add(jobPk);
      final steps = <int>[];
      for (var s = 0; s < job.steps.length; s++) {
        final step = job.steps[s];
        final stepPk = await db.createCiStep(CiStepsCompanion.insert(
          ci_job_fk: jobPk,
          name: step.name,
          orderIndex: Value(s),
          command: Value(step.run ?? (step.uses != null ? 'uses: ${step.uses}' : null)),
        ));
        steps.add(stepPk);
      }
      stepPks.add(steps);
    }

    final cancel = CiCancelToken();
    unawaited(_runWorkflow(
      runPk: runPk,
      plan: plan,
      ws: ws,
      jobPks: jobPks,
      stepPks: stepPks,
      taskPk: taskPk,
      cancel: cancel,
    ));
    return StartedRun(runPk, cancel);
  }

  Future<void> _runWorkflow({
    required int runPk,
    required WorkflowPlan plan,
    required Workspace ws,
    required List<int> jobPks,
    required List<List<int>> stepPks,
    int? taskPk,
    required CiCancelToken cancel,
  }) async {
    MaterializedWorkspace? mat;
    final now = DateTime.now();
    try {
      await db.patchCiRun(runPk, CiRunsCompanion(status: const Value('running'), startedAt: Value(now)));

      mat = await materializer.materialize(ws, tag: 'workflow');

      final outcome = await workflowRunner.run(
        plan,
        workDir: mat.path,
        log: _logSink(stepPks),
        cancel: cancel,
        onStepStatus: (j, s, status) {
          if (j < stepPks.length && s < stepPks[j].length) {
            db.patchCiStep(stepPks[j][s], CiStepsCompanion(
              status: Value(status.wire),
              startedAt: status == CiStatus.running ? Value(DateTime.now()) : const Value.absent(),
              completedAt: status.isTerminal ? Value(DateTime.now()) : const Value.absent(),
            ));
          }
        },
        onJobStatus: (j, status) {
          if (j < jobPks.length) {
            db.patchCiJob(jobPks[j], CiJobsCompanion(
              status: Value(status.wire),
              startedAt: status == CiStatus.running ? Value(DateTime.now()) : const Value.absent(),
              completedAt: status.isTerminal ? Value(DateTime.now()) : const Value.absent(),
            ));
          }
        },
      );
      await _finalize(runPk, jobPks, stepPks, outcome, startedAt: now, taskPk: taskPk);
    } catch (e) {
      await _failAll(runPk, jobPks, stepPks, error: '$e', taskPk: taskPk);
    } finally {
      await mat?.dispose();
    }
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// Build a log sink that appends each line to the step it targets. Lines with
  /// no indices (run-level / system) fall back to the first step.
  CiLogSink _logSink(List<List<int>> stepPks) {
    int? resolve(int? j, int? s) {
      if (j != null && s != null && j < stepPks.length && s < stepPks[j].length) {
        return stepPks[j][s];
      }
      if (stepPks.isNotEmpty && stepPks.first.isNotEmpty) return stepPks.first.first;
      return null;
    }

    return (event) {
      final pk = resolve(event.jobIndex, event.stepIndex);
      if (pk == null) return;
      final prefix = event.stream == CiLogStream.system ? '» ' : '';
      db.appendCiStepLog(pk, '$prefix${event.line}\n');
    };
  }

  Future<void> _markRunning(int runPk, int jobPk, int stepPk) async {
    final now = DateTime.now();
    await db.patchCiRun(runPk, CiRunsCompanion(status: const Value('running'), startedAt: Value(now)));
    await db.patchCiJob(jobPk, CiJobsCompanion(status: const Value('running'), startedAt: Value(now)));
    await db.patchCiStep(stepPk, CiStepsCompanion(status: const Value('running'), startedAt: Value(now)));
  }

  /// Reconcile every row from the backend/runner outcome and stamp completion.
  Future<void> _finalize(
    int runPk,
    List<int> jobPks,
    List<List<int>> stepPks,
    CiRunOutcome outcome, {
    required DateTime startedAt,
    int? taskPk,
  }) async {
    final now = DateTime.now();
    for (var j = 0; j < outcome.jobs.length && j < jobPks.length; j++) {
      final job = outcome.jobs[j];
      await db.patchCiJob(jobPks[j], CiJobsCompanion(
        status: Value(job.status.wire),
        completedAt: Value(now),
      ));
      for (var s = 0; s < job.steps.length && j < stepPks.length && s < stepPks[j].length; s++) {
        final step = job.steps[s];
        await db.patchCiStep(stepPks[j][s], CiStepsCompanion(
          status: Value(step.status.wire),
          exitCode: Value(step.exitCode),
          completedAt: Value(now),
        ));
      }
    }
    await db.patchCiRun(runPk, CiRunsCompanion(
      status: Value(outcome.status.wire),
      errorText: Value(outcome.error),
      completedAt: Value(now),
    ));
    // Auto-complete an attached task: green → Done, anything else → back to board.
    if (taskPk != null) {
      await db.recordTaskBuildResult(taskPk, passed: outcome.status == CiStatus.success);
    }
  }

  Future<void> _failAll(
    int runPk,
    List<int> jobPks,
    List<List<int>> stepPks, {
    required String error,
    int? taskPk,
  }) async {
    final now = DateTime.now();
    for (var j = 0; j < jobPks.length; j++) {
      await db.patchCiJob(jobPks[j], CiJobsCompanion(status: const Value('failed'), completedAt: Value(now)));
      for (final stepPk in stepPks[j]) {
        await db.patchCiStep(stepPk, CiStepsCompanion(status: const Value('failed'), completedAt: Value(now)));
      }
    }
    await db.patchCiRun(runPk, CiRunsCompanion(
      status: const Value('failed'),
      errorText: Value(error),
      completedAt: Value(now),
    ));
    if (taskPk != null) {
      await db.recordTaskBuildResult(taskPk, passed: false);
    }
  }

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}

/// Local re-implementation of `dart:async`'s `unawaited` to avoid an import just
/// for it: intentionally start a future without awaiting it.
void unawaited(Future<void> future) {}
