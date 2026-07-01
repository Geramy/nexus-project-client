// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';
import 'dart:io';

import 'process_runner.dart';

/// Run a shell [script] to completion and return its exit code + FULL combined
/// output. Captures via a temp SCRIPT FILE that redirects both streams to a file
/// (`(<script>) > file 2>&1`), then reads the file — this app is a console-less
/// GUI process, so the child's STDOUT pipe is dropped; the shell's own file
/// redirect isn't. Tolerant decode so odd bytes never drop lines.
///
/// Live streaming is sacrificed for reliability — use for one-shot builds where
/// the final log + exit code are what matter.
Future<({int exitCode, String output})> runCaptured(
  String script, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration? timeout,
}) async {
  final tmp = await Directory.systemTemp.createTemp('nxs_run_');
  final logPath = '${tmp.path}${Platform.pathSeparator}out.log';
  final String executable;
  final List<String> args;
  if (Platform.isWindows) {
    final sp = '${tmp.path}\\run.cmd';
    await File(
      sp,
    ).writeAsString('@echo off\r\n(\r\n$script\r\n) 1> "$logPath" 2>&1\r\n');
    executable = 'cmd';
    args = ['/C', sp];
  } else {
    final sp = '${tmp.path}/run.sh';
    await File(sp).writeAsString('{\n$script\n} > "$logPath" 2>&1\n');
    executable = 'bash';
    args = [sp];
  }

  var output = '';
  var code = -1;
  try {
    final result = await const ProcessRunner().run(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
    );
    code = result.exitCode;
    try {
      final f = File(logPath);
      if (await f.exists()) {
        output = const Utf8Decoder(
          allowMalformed: true,
        ).convert(await f.readAsBytes());
      }
    } catch (_) {}
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
  return (exitCode: code, output: output);
}
