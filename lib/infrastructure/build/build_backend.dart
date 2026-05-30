// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';

import 'build_models.dart';

/// A cooperative cancellation signal handed to a running backend. The backend
/// should poll [isCancelled] between steps and/or await [whenCancelled] to abort
/// long-running child processes early.
class CiCancelToken {
  final Completer<void> _c = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _c.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_c.isCompleted) _c.complete();
  }
}

/// Executes build runs. Two implementations:
///   - LocalDockerBackend — shells out to the local `docker` CLI.
///   - RemoteBuildBackend — delegates to a remote build server over HTTP.
///
/// A backend is given a [CiRunRequest] whose `workDir` already contains the
/// materialized project files, emits log lines through [log] as it works, and
/// returns the structured [CiRunOutcome]. Orchestration (materializing the
/// workspace, persisting runs/jobs/steps/logs to the DB, exposing live streams)
/// lives one layer up in the build service — backends stay focused on execution.
abstract interface class BuildBackend {
  CiBackendKind get kind;

  /// Is this backend usable right now? (e.g. local Docker checks `docker`
  /// is installed and the daemon is reachable.) Returns null when ready, or a
  /// human-readable reason when not.
  Future<String?> unavailableReason();

  /// Execute [request], streaming log lines via [log]. Honors [cancel].
  Future<CiRunOutcome> execute(
    CiRunRequest request, {
    required CiLogSink log,
    CiCancelToken? cancel,
  });
}
