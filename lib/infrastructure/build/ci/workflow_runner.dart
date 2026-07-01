// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';
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
        final downstreamStatus = runCancelled
            ? CiStatus.cancelled
            : CiStatus.skipped;
        onJobStatus?.call(j, downstreamStatus);
        final steps = <CiStepOutcome>[];
        for (var s = 0; s < job.steps.length; s++) {
          onStepStatus?.call(j, s, downstreamStatus);
          steps.add(
            CiStepOutcome(name: job.steps[s].name, status: downstreamStatus),
          );
        }
        jobOutcomes.add(
          CiJobOutcome(name: job.name, status: downstreamStatus, steps: steps),
        );
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
          stepOutcomes.add(
            CiStepOutcome(name: step.name, status: CiStatus.cancelled),
          );
          jobCancelled = true;
          continue;
        }

        onStepStatus?.call(j, s, CiStatus.running);

        // A `uses:` step with no `run:` — external actions are unsupported.
        if ((step.run == null || step.run!.trim().isEmpty) &&
            step.uses != null) {
          log(
            CiLogEvent(
              'Skipping action "${step.uses}" — external actions are not supported in the local runner.',
              jobIndex: j,
              stepIndex: s,
              stream: CiLogStream.system,
            ),
          );
          onStepStatus?.call(j, s, CiStatus.skipped);
          stepOutcomes.add(
            CiStepOutcome(name: step.name, status: CiStatus.skipped),
          );
          continue;
        }

        // Nothing to do — neither run nor uses.
        if (step.run == null || step.run!.trim().isEmpty) {
          log(
            CiLogEvent(
              'Step "${step.name}" has no run script — skipping.',
              jobIndex: j,
              stepIndex: s,
              stream: CiLogStream.system,
            ),
          );
          onStepStatus?.call(j, s, CiStatus.skipped);
          stepOutcomes.add(
            CiStepOutcome(name: step.name, status: CiStatus.skipped),
          );
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
      jobOutcomes.add(
        CiJobOutcome(name: job.name, status: jobStatus, steps: stepOutcomes),
      );

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

    log(
      CiLogEvent(
        '\$ $script',
        jobIndex: jobIndex,
        stepIndex: stepIndex,
        stream: CiLogStream.system,
      ),
    );

    final environment = step.env.isEmpty
        ? null
        : Map<String, String>.from(step.env);

    // Capture the step's output via a TEMP FILE rather than the live stdout/
    // stderr pipes. This app runs as a Windows GUI process with NO attached
    // console, and in that mode the child process's STDOUT pipe is dropped — only
    // STDERR survives. Tools like `flutter analyze` print every diagnostic to
    // STDOUT (only the "N issues found" summary to stderr), so pipe capture lost
    // ALL the actual errors and the CI gate / end-of-project fixer saw nothing.
    // Redirecting both streams to a file (done by the shell itself, which writes
    // the file regardless of the parent's console state) and reading it back is
    // immune to that. Read tolerant of malformed bytes so non-UTF-8 output never
    // drops lines.
    final tmpDir = await Directory.systemTemp.createTemp('nxs_ci_');
    final logPath = '${tmpDir.path}${Platform.pathSeparator}step.log';
    // Write the step into a SCRIPT FILE that redirects its own output to a file,
    // then execute the file. Doing the redirect inline (`cmd /C "(...) > "path""`)
    // breaks on cmd.exe's nested-quote handling ("filename syntax is incorrect").
    // Inside a .cmd/.sh the quotes parse normally, and the file redirect reliably
    // captures stdout — which a console-less GUI app otherwise drops from the
    // child pipe.
    final String executable;
    final List<String> args;
    if (Platform.isWindows) {
      final sp = '${tmpDir.path}\\step.cmd';
      await File(
        sp,
      ).writeAsString('@echo off\r\n(\r\n$script\r\n) 1> "$logPath" 2>&1\r\n');
      executable = 'cmd';
      args = ['/C', sp];
    } else {
      final sp = '${tmpDir.path}/step.sh';
      await File(sp).writeAsString('{\n$script\n} > "$logPath" 2>&1\n');
      executable = step.shell == 'sh' ? 'sh' : 'bash';
      args = [sp];
    }

    try {
      final result = await runner.run(
        executable,
        args,
        workingDirectory: workDir,
        environment: environment,
        includeParentEnvironment: true,
        cancel: cancel?.whenCancelled,
        onLine: (l) {
          // With the file redirect the pipes are usually empty, but emit any
          // stray bytes that do leak through so nothing is silently lost.
          log(
            CiLogEvent(
              l.text,
              jobIndex: jobIndex,
              stepIndex: stepIndex,
              stream: l.stream == ProcStream.stdout
                  ? CiLogStream.stdout
                  : CiLogStream.stderr,
            ),
          );
        },
      );

      // Drain the captured output file into the log (the real diagnostics).
      try {
        final f = File(logPath);
        final exists = await f.exists();
        final text = exists
            ? const Utf8Decoder(allowMalformed: true).convert(
                await f.readAsBytes(),
              )
            : '';
        if (exists && text.trim().isNotEmpty) {
          // Emit the whole captured output as ONE event. The log sink fires an
          // UNAWAITED read-modify-write append per event, so emitting line-by-line
          // races dozens of concurrent appends that clobber each other (only the
          // last survives — which is why just the "N issues found" summary was
          // persisted). One append writes the entire block atomically.
          log(
            CiLogEvent(
              text.trimRight(),
              jobIndex: jobIndex,
              stepIndex: stepIndex,
              stream: CiLogStream.stdout,
            ),
          );
        }
      } catch (_) {
        // Best-effort capture; never fail a step over log readback.
      } finally {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {}
      }

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
        log(
          CiLogEvent(
            'Step "${step.name}" timed out.',
            jobIndex: jobIndex,
            stepIndex: stepIndex,
            stream: CiLogStream.system,
          ),
        );
      }

      return CiStepOutcome(
        name: step.name,
        status: status,
        exitCode: result.exitCode,
      );
    } on ProcessSpawnException catch (e) {
      log(
        CiLogEvent(
          'Failed to start shell for step "${step.name}": $e',
          jobIndex: jobIndex,
          stepIndex: stepIndex,
          stream: CiLogStream.system,
        ),
      );
      return CiStepOutcome(name: step.name, status: CiStatus.failed);
    }
  }

}
