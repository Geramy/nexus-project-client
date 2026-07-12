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

/// The current user's Desktop directory (respects OneDrive redirection). Falls
/// back to `%USERPROFILE%\Desktop`.
Future<String> desktopDir() async {
  if (Platform.isWindows) {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[Environment]::GetFolderPath("Desktop")',
      ]);
      final p = (r.stdout as String).trim();
      if (p.isNotEmpty) return p;
    } catch (_) {}
    final home = Platform.environment['USERPROFILE'] ?? '';
    return home.isEmpty ? '' : '$home\\Desktop';
  }
  final home = Platform.environment['HOME'] ?? '';
  return home.isEmpty ? '' : '$home/Desktop';
}

/// Native "choose a folder" dialog. Returns the picked path, or null if the user
/// cancelled. Windows-only (Shell.Application COM); returns null elsewhere.
Future<String?> pickFolder(String title) async {
  if (!Platform.isWindows) return null;
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-STA',
      '-Command',
      // BrowseForFolder(hwnd, title, options, rootFolder). 0x51 = show edit box +
      // new-style dialog. Print the selected path (empty on cancel).
      r'$s = New-Object -ComObject Shell.Application; '
          r'$f = $s.BrowseForFolder(0, "' +
          title.replaceAll('"', "'") +
          r'", 0x51, 0); '
          r'if ($f) { $f.Self.Path }',
    ]);
    final p = (r.stdout as String).trim();
    return p.isEmpty ? null : p;
  } catch (_) {
    return null;
  }
}

/// Create a Windows .lnk shortcut at [linkPath] pointing at [targetPath] (with
/// [workingDir] as its start-in dir), so the built app is double-clickable from
/// the Desktop. Best-effort; Windows-only.
Future<void> createShortcut(
  String linkPath,
  String targetPath, {
  String? workingDir,
}) async {
  if (!Platform.isWindows) return;
  try {
    final wd = workingDir ?? File(targetPath).parent.path;
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'$w = New-Object -ComObject WScript.Shell; '
          r'$sc = $w.CreateShortcut("' +
          linkPath.replaceAll('"', '') +
          r'"); $sc.TargetPath = "' +
          targetPath.replaceAll('"', '') +
          r'"; $sc.WorkingDirectory = "' +
          wd.replaceAll('"', '') +
          r'"; $sc.Save()',
    ]);
  } catch (_) {}
}

/// Recursively copy [src] into [dst] (created if missing). Used to lift a built
/// Windows app bundle (exe + DLLs + data/) out of the temp build dir into a
/// user-chosen, permanent location.
Future<void> copyDirectory(Directory src, Directory dst) async {
  await dst.create(recursive: true);
  await for (final entity in src.list(followLinks: false)) {
    final name = entity.path
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .last;
    if (entity is Directory) {
      await copyDirectory(
        entity,
        Directory('${dst.path}${Platform.pathSeparator}$name'),
      );
    } else if (entity is File) {
      await entity.copy('${dst.path}${Platform.pathSeparator}$name');
    }
  }
}
