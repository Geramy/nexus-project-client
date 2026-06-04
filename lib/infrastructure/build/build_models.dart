// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Shared value types for the build / CI subsystem.
///
/// These model a GitHub-Actions-shaped run hierarchy — a *run* contains one or
/// more *jobs*, each of which runs an ordered list of *steps* — plus the
/// streaming log events emitted while a run executes. Both the build backends
/// (local Docker / remote) and the local CI workflow runner produce these same
/// types so the persistence layer and UI are agnostic to how a run was made.
library;

/// Lifecycle status of a run, job, or step. Mirrors the string values stored in
/// the `status` columns of the CiRuns / CiJobs / CiSteps tables.
enum CiStatus { pending, running, success, failed, cancelled, skipped }

extension CiStatusX on CiStatus {
  String get wire => name;
  bool get isTerminal =>
      this == CiStatus.success ||
      this == CiStatus.failed ||
      this == CiStatus.cancelled ||
      this == CiStatus.skipped;
  bool get isFailure => this == CiStatus.failed || this == CiStatus.cancelled;

  static CiStatus fromWire(String? s) {
    for (final v in CiStatus.values) {
      if (v.name == s) return v;
    }
    return CiStatus.pending;
  }
}

/// What kind of work a run performs.
enum CiRunKind {
  /// Build a single Dockerfile (`docker build`).
  dockerBuild,

  /// Execute a GitHub-Actions-format workflow locally.
  workflow,
}

extension CiRunKindX on CiRunKind {
  String get wire => name;
  static CiRunKind fromWire(String? s) {
    for (final v in CiRunKind.values) {
      if (v.name == s) return v;
    }
    return CiRunKind.dockerBuild;
  }
}

/// Which backend executed (or will execute) a run.
enum CiBackendKind {
  /// Local Docker daemon via the `docker` CLI.
  localDocker,

  /// Remote build server over HTTP.
  remote,
}

extension CiBackendKindX on CiBackendKind {
  String get wire => name;
  static CiBackendKind fromWire(String? s) {
    for (final v in CiBackendKind.values) {
      if (v.name == s) return v;
    }
    return CiBackendKind.localDocker;
  }
}

/// Which stream a log line came from.
enum CiLogStream { stdout, stderr, system }

extension CiLogStreamX on CiLogStream {
  String get wire => name;
  static CiLogStream fromWire(String? s) {
    for (final v in CiLogStream.values) {
      if (v.name == s) return v;
    }
    return CiLogStream.stdout;
  }
}

/// A single streamed log line. [jobIndex]/[stepIndex] locate the line within the
/// run hierarchy; both null means a run-level (orchestration) line.
class CiLogEvent {
  final int? jobIndex;
  final int? stepIndex;
  final CiLogStream stream;
  final String line;
  final DateTime at;

  CiLogEvent(
    this.line, {
    this.jobIndex,
    this.stepIndex,
    this.stream = CiLogStream.stdout,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// A run-level system line (orchestration / status messages).
  factory CiLogEvent.system(String line) =>
      CiLogEvent(line, stream: CiLogStream.system);
}

/// Sink a backend/runner uses to emit log lines as it works.
typedef CiLogSink = void Function(CiLogEvent event);

/// A request to execute a run. [workDir] is a real host directory the workspace
/// has already been materialized into (see WorkspaceMaterializer) — backends and
/// the runner read real files from there. Paths inside are relative to [workDir].
class CiRunRequest {
  final CiRunKind kind;
  final String workDir;

  /// Docker build: path to the Dockerfile relative to [workDir] (e.g. `Dockerfile`).
  final String? dockerfilePath;

  /// Docker build: the image tag to produce (e.g. `myproject:latest`).
  final String? imageTag;

  /// Build context dir relative to [workDir] (defaults to `.`).
  final String buildContext;

  /// `--build-arg` values for a Docker build.
  final Map<String, String> buildArgs;

  /// Workflow run: path to the workflow YAML relative to [workDir]
  /// (e.g. `.github/workflows/ci.yml`).
  final String? workflowPath;

  /// Optional branch / commit this run targets (for display + provenance).
  final String? branch;
  final String? commitOid;

  const CiRunRequest({
    required this.kind,
    required this.workDir,
    this.dockerfilePath,
    this.imageTag,
    this.buildContext = '.',
    this.buildArgs = const {},
    this.workflowPath,
    this.branch,
    this.commitOid,
  });
}

/// Result of a finished step.
class CiStepOutcome {
  final String name;
  final CiStatus status;
  final int? exitCode;
  const CiStepOutcome({
    required this.name,
    required this.status,
    this.exitCode,
  });
}

/// Result of a finished job.
class CiJobOutcome {
  final String name;
  final CiStatus status;
  final List<CiStepOutcome> steps;
  const CiJobOutcome({
    required this.name,
    required this.status,
    this.steps = const [],
  });
}

/// Final result of a run.
class CiRunOutcome {
  final CiStatus status;
  final List<CiJobOutcome> jobs;

  /// Set when the run failed to even start (e.g. docker not installed).
  final String? error;

  const CiRunOutcome({required this.status, this.jobs = const [], this.error});

  factory CiRunOutcome.failedToStart(String error) =>
      CiRunOutcome(status: CiStatus.failed, error: error);
}
