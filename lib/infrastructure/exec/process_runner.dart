// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Origin of a streamed output line.
enum ProcStream { stdout, stderr }

/// One line of process output, tagged with its stream.
class ProcLine {
  final ProcStream stream;
  final String text;
  const ProcLine(this.stream, this.text);
}

/// Final result of a finished process.
class ProcResult {
  final int exitCode;
  final bool timedOut;
  final bool cancelled;
  const ProcResult({
    required this.exitCode,
    this.timedOut = false,
    this.cancelled = false,
  });

  bool get ok => exitCode == 0 && !timedOut && !cancelled;
}

/// Thrown when a process cannot be spawned at all (e.g. the executable is not on
/// PATH). Distinct from a non-zero exit, which is a normal [ProcResult].
class ProcessSpawnException implements Exception {
  final String executable;
  final Object cause;
  ProcessSpawnException(this.executable, this.cause);
  @override
  String toString() => 'Failed to start "$executable": $cause';
}

/// The app's process-execution capability — a thin, streaming wrapper over
/// `dart:io` Process. The rest of the app is purely in-process (files live in a
/// SQLite virtual disk); this is the one place that shells out, used by the
/// Docker backend and the local CI runner to invoke `docker`, build tools, etc.
///
/// Everything is line-oriented and streamed so the UI can show live logs and a
/// run can be cancelled or time out mid-flight.
class ProcessRunner {
  const ProcessRunner();

  /// Spawn [executable] with [args] and stream merged stdout/stderr lines while
  /// it runs, completing with the [ProcResult] when it exits.
  ///
  /// - [workingDirectory]: cwd for the child process.
  /// - [environment]/[includeParentEnvironment]: env control.
  /// - [onLine]: called for each decoded output line (stdout or stderr).
  /// - [timeout]: kill the process (SIGKILL) if it runs longer than this.
  /// - [cancel]: when this future completes, the process is killed.
  Future<ProcResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    void Function(ProcLine line)? onLine,
    Duration? timeout,
    Future<void>? cancel,
  }) async {
    final Process proc;
    try {
      proc = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: false,
      );
    } catch (e) {
      throw ProcessSpawnException(executable, e);
    }

    var timedOut = false;
    var cancelled = false;

    void killTree() {
      // SIGKILL the process. (Child grandchildren — e.g. a docker daemon's work
      // — are managed by the daemon, not us, so killing the CLI is sufficient.)
      proc.kill(ProcessSignal.sigkill);
    }

    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        timedOut = true;
        killTree();
      });
    }

    StreamSubscription<void>? cancelSub;
    if (cancel != null) {
      cancelSub = cancel.asStream().listen((_) {
        cancelled = true;
        killTree();
      });
    }

    final stdoutDone = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => onLine?.call(ProcLine(ProcStream.stdout, l)))
        .asFuture<void>();
    final stderrDone = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => onLine?.call(ProcLine(ProcStream.stderr, l)))
        .asFuture<void>();

    final exitCode = await proc.exitCode;
    // Drain remaining buffered output before reporting completion.
    await Future.wait([stdoutDone, stderrDone]);
    timer?.cancel();
    await cancelSub?.cancel();

    return ProcResult(
      exitCode: exitCode,
      timedOut: timedOut,
      cancelled: cancelled,
    );
  }

  /// Run a process to completion and capture all stdout (trimmed). Convenience
  /// for short commands like `docker --version`. Returns null on non-zero exit
  /// or spawn failure.
  Future<String?> capture(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final buf = StringBuffer();
    try {
      final res = await run(
        executable,
        args,
        workingDirectory: workingDirectory,
        timeout: timeout,
        onLine: (l) {
          if (l.stream == ProcStream.stdout) buf.writeln(l.text);
        },
      );
      if (!res.ok) return null;
    } catch (_) {
      return null;
    }
    return buf.toString().trim();
  }
}
