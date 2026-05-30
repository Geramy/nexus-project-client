// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import '../build_backend.dart';
import '../build_models.dart';
import '../../exec/process_runner.dart';
import 'workflow_model.dart';

/// Executes a parsed [WorkflowPlan] locally on the host, shelling out to a real
/// shell for each `run:` step via [ProcessRunner].
///
/// This is a mini-`act`: jobs and steps run sequentially in the materialized
/// [workDir], `uses:` (external action) steps are skipped, and a failed `run:`
/// step fails its job and stops the whole run (GitHub's default fail-fast),
/// marking everything downstream `skipped`.
class WorkflowRunner {
  final ProcessRunner runner;

  const WorkflowRunner({this.runner = const ProcessRunner()});

  /// Run [plan] in [workDir], streaming log lines through [log].
  ///
  /// [onStepStatus]/[onJobStatus] (if provided) are fired with
  /// [CiStatus.running] as each job/step starts and with the final status as it
  /// settles. Honors [cancel].
  Future<CiRunOutcome> run(
    WorkflowPlan plan, {
    required String workDir,
    required CiLogSink log,
    CiCancelToken? cancel,
    void Function(int jobIndex, int stepIndex, CiStatus status)? onStepStatus,
    void Function(int jobIndex, CiStatus status)? onJobStatus,
  }) async {
    final jobOutcomes = <CiJobOutcome>[];
    var runCancelled = false;
    var runFailed = false;

    for (var j = 0; j < plan.jobs.length; j++) {
      final job = plan.jobs[j];

      // If a prior job failed (fail-fast) or the run was cancelled, mark this
      // job and all its steps as skipped/cancelled without running anything.
      if (runFailed || runCancelled) {
        final downstreamStatus =
            runCancelled ? CiStatus.cancelled : CiStatus.skipped;
        onJobStatus?.call(j, downstreamStatus);
        final steps = <CiStepOutcome>[];
        for (var s = 0; s < job.steps.length; s++) {
          onStepStatus?.call(j, s, downstreamStatus);
          steps.add(CiStepOutcome(
            name: job.steps[s].name,
            status: downstreamStatus,
          ));
        }
        jobOutcomes.add(CiJobOutcome(
          name: job.name,
          status: downstreamStatus,
          steps: steps,
        ));
        continue;
      }

      onJobStatus?.call(j, CiStatus.running);
      log(CiLogEvent.system('Job "${job.name}" started.'));

      final stepOutcomes = <CiStepOutcome>[];
      var jobFailed = false;
      var jobCancelled = false;

      for (var s = 0; s < job.steps.length; s++) {
        final step = job.steps[s];

        // Downstream steps after a failure / cancellation.
        if (jobFailed || jobCancelled) {
          final status = jobCancelled ? CiStatus.cancelled : CiStatus.skipped;
          onStepStatus?.call(j, s, status);
          stepOutcomes.add(CiStepOutcome(name: step.name, status: status));
          continue;
        }

        // Cancellation check before starting the step.
        if (cancel?.isCancelled ?? false) {
          onStepStatus?.call(j, s, CiStatus.cancelled);
          stepOutcomes
              .add(CiStepOutcome(name: step.name, status: CiStatus.cancelled));
          jobCancelled = true;
          continue;
        }

        onStepStatus?.call(j, s, CiStatus.running);

        // A `uses:` step with no `run:` — external actions are unsupported.
        if ((step.run == null || step.run!.trim().isEmpty) &&
            step.uses != null) {
          log(CiLogEvent(
            'Skipping action "${step.uses}" — external actions are not supported in the local runner.',
            jobIndex: j,
            stepIndex: s,
            stream: CiLogStream.system,
          ));
          onStepStatus?.call(j, s, CiStatus.skipped);
          stepOutcomes
              .add(CiStepOutcome(name: step.name, status: CiStatus.skipped));
          continue;
        }

        // Nothing to do — neither run nor uses.
        if (step.run == null || step.run!.trim().isEmpty) {
          log(CiLogEvent(
            'Step "${step.name}" has no run script — skipping.',
            jobIndex: j,
            stepIndex: s,
            stream: CiLogStream.system,
          ));
          onStepStatus?.call(j, s, CiStatus.skipped);
          stepOutcomes
              .add(CiStepOutcome(name: step.name, status: CiStatus.skipped));
          continue;
        }

        final outcome = await _runStep(
          step: step,
          jobIndex: j,
          stepIndex: s,
          workDir: workDir,
          log: log,
          cancel: cancel,
        );

        onStepStatus?.call(j, s, outcome.status);
        stepOutcomes.add(outcome);

        switch (outcome.status) {
          case CiStatus.cancelled:
            jobCancelled = true;
            break;
          case CiStatus.failed:
            jobFailed = true;
            break;
          default:
            break;
        }
      }

      final jobStatus = jobCancelled
          ? CiStatus.cancelled
          : jobFailed
              ? CiStatus.failed
              : CiStatus.success;
      onJobStatus?.call(j, jobStatus);
      log(CiLogEvent.system('Job "${job.name}" ${jobStatus.name}.'));
      jobOutcomes.add(CiJobOutcome(
        name: job.name,
        status: jobStatus,
        steps: stepOutcomes,
      ));

      if (jobCancelled) runCancelled = true;
      if (jobFailed) runFailed = true;
    }

    final runStatus = runCancelled
        ? CiStatus.cancelled
        : runFailed
            ? CiStatus.failed
            : CiStatus.success;

    return CiRunOutcome(status: runStatus, jobs: jobOutcomes);
  }

  Future<CiStepOutcome> _runStep({
    required WorkflowStep step,
    required int jobIndex,
    required int stepIndex,
    required String workDir,
    required CiLogSink log,
    CiCancelToken? cancel,
  }) async {
    final script = step.run!;
    final (executable, args) = _shellFor(step.shell, script);

    log(CiLogEvent(
      '\$ $executable ${args.join(' ')}',
      jobIndex: jobIndex,
      stepIndex: stepIndex,
      stream: CiLogStream.system,
    ));

    final environment = step.env.isEmpty ? null : Map<String, String>.from(step.env);

    try {
      final result = await runner.run(
        executable,
        args,
        workingDirectory: workDir,
        environment: environment,
        includeParentEnvironment: true,
        cancel: cancel?.whenCancelled,
        onLine: (l) {
          log(CiLogEvent(
            l.text,
            jobIndex: jobIndex,
            stepIndex: stepIndex,
            stream: l.stream == ProcStream.stdout
                ? CiLogStream.stdout
                : CiLogStream.stderr,
          ));
        },
      );

      final CiStatus status;
      if (result.cancelled) {
        status = CiStatus.cancelled;
      } else if (result.timedOut) {
        status = CiStatus.failed;
      } else if (result.ok) {
        status = CiStatus.success;
      } else {
        status = CiStatus.failed;
      }

      if (result.timedOut) {
        log(CiLogEvent(
          'Step "${step.name}" timed out.',
          jobIndex: jobIndex,
          stepIndex: stepIndex,
          stream: CiLogStream.system,
        ));
      }

      return CiStepOutcome(
        name: step.name,
        status: status,
        exitCode: result.exitCode,
      );
    } on ProcessSpawnException catch (e) {
      log(CiLogEvent(
        'Failed to start shell for step "${step.name}": $e',
        jobIndex: jobIndex,
        stepIndex: stepIndex,
        stream: CiLogStream.system,
      ));
      return CiStepOutcome(name: step.name, status: CiStatus.failed);
    }
  }

  /// Pick the shell executable + args for a `run:` script.
  ///
  /// `sh` uses `sh -c <script>`; everything else defaults to `bash -lc <script>`
  /// on macOS/Linux. On Windows, fall back to `cmd /C`.
  (String, List<String>) _shellFor(String? shell, String script) {
    if (Platform.isWindows) {
      return ('cmd', ['/C', script]);
    }
    if (shell == 'sh') {
      return ('sh', ['-c', script]);
    }
    return ('bash', ['-lc', script]);
  }
}
