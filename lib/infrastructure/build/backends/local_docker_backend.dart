// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import '../build_backend.dart';
import '../build_models.dart';
import '../../exec/process_runner.dart';

/// A [BuildBackend] that executes `docker build` against the local Docker
/// daemon by shelling out to the `docker` CLI via [ProcessRunner].
///
/// Only handles [CiRunKind.dockerBuild] runs; workflow runs are the domain of
/// the local CI workflow runner, not this backend.
class LocalDockerBackend implements BuildBackend {
  final ProcessRunner runner;

  const LocalDockerBackend({this.runner = const ProcessRunner()});

  @override
  CiBackendKind get kind => CiBackendKind.localDocker;

  @override
  Future<String?> unavailableReason() async {
    final version = await runner.capture('docker', ['--version']);
    if (version != null) return null;
    return 'Docker CLI not found on PATH or Docker is not running.';
  }

  @override
  Future<CiRunOutcome> execute(
    CiRunRequest request, {
    required CiLogSink log,
    CiCancelToken? cancel,
  }) async {
    if (request.kind != CiRunKind.dockerBuild) {
      return CiRunOutcome.failedToStart(
        'LocalDockerBackend only handles docker builds',
      );
    }

    final imageTag = request.imageTag;
    final dockerfilePath = request.dockerfilePath;
    final buildContext =
        request.buildContext.isEmpty ? '.' : request.buildContext;

    // Assemble: docker build -t <tag> -f <dockerfile> [--build-arg k=v ...] <ctx>
    final args = <String>['build'];
    if (imageTag != null && imageTag.isNotEmpty) {
      args.addAll(['-t', imageTag]);
    }
    if (dockerfilePath != null && dockerfilePath.isNotEmpty) {
      args.addAll(['-f', dockerfilePath]);
    }
    request.buildArgs.forEach((k, v) {
      args.addAll(['--build-arg', '$k=$v']);
    });
    args.add(buildContext);

    log(CiLogEvent.system('\$ docker ${args.join(' ')}'));

    final ProcResult res;
    try {
      res = await runner.run(
        'docker',
        args,
        workingDirectory: request.workDir,
        onLine: (l) {
          log(
            CiLogEvent(
              l.text,
              jobIndex: 0,
              stepIndex: 0,
              stream: l.stream == ProcStream.stdout
                  ? CiLogStream.stdout
                  : CiLogStream.stderr,
            ),
          );
        },
        cancel: cancel?.whenCancelled,
      );
    } on ProcessSpawnException catch (e) {
      log(CiLogEvent('Failed to start docker: $e', stream: CiLogStream.system));
      return CiRunOutcome.failedToStart('Failed to start docker: $e');
    }

    final CiStatus status;
    if (res.cancelled) {
      status = CiStatus.cancelled;
    } else if (res.timedOut) {
      status = CiStatus.failed;
    } else if (res.ok) {
      status = CiStatus.success;
    } else {
      status = CiStatus.failed;
    }

    return CiRunOutcome(
      status: status,
      jobs: [
        CiJobOutcome(
          name: 'build',
          status: status,
          steps: [
            CiStepOutcome(
              name: 'docker build',
              status: status,
              exitCode: res.exitCode,
            ),
          ],
        ),
      ],
    );
  }
}
