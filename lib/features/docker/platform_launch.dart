// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

/// Open [url] in the user's default browser. No url_launcher dependency — shell
/// out to the platform opener (works from a console-less desktop app).
Future<void> openUrl(String url) async {
  if (Platform.isWindows) {
    // `explorer.exe <http-url>` hands the URL to the default protocol handler
    // (the browser) and — unlike `cmd /C start` — works reliably from a
    // console-less GUI process (it's what the "reveal in file manager" button
    // uses). explorer returns a non-zero exit even on success, so fire-and-forget
    // detached and don't inspect the code.
    await Process.start(
      'explorer.exe',
      [url],
      mode: ProcessStartMode.detached,
    );
  } else if (Platform.isMacOS) {
    await Process.start('open', [url]);
  } else {
    await Process.start('xdg-open', [url]);
  }
}

/// Launch a built executable [exePath] as a detached process (its own window),
/// working from its own directory so it finds sibling data/DLLs.
Future<void> launchExecutable(String exePath) async {
  final dir = File(exePath).parent.path;
  await Process.start(
    exePath,
    const [],
    workingDirectory: dir,
    mode: ProcessStartMode.detached,
  );
}

/// Reveal [path] (a file or folder) in the OS file manager.
Future<void> revealInFileManager(String path) async {
  if (Platform.isWindows) {
    await Process.start('explorer', [path]);
  } else if (Platform.isMacOS) {
    await Process.start('open', [path]);
  } else {
    await Process.start('xdg-open', [path]);
  }
}
