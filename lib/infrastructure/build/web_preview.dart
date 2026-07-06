// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';
import 'dart:typed_data';

import '../workspace/workspace.dart';
import '../exec/captured_run.dart';
import 'workspace_materializer.dart';

/// Build the project as a Flutter WEB app, serve it locally, and capture a
/// headless-Chrome screenshot of the running app — so a vision model can look at
/// what actually renders. Returns the PNG bytes, or null if the build/capture
/// couldn't run (no Chrome, build failed, not a Flutter project). Best-effort:
/// callers should treat null as "no screenshot available" and carry on.
class WebPreviewResult {
  final Uint8List? png;
  final String log; // build/capture log (for surfacing build failures)
  const WebPreviewResult(this.png, this.log);
}

Future<WebPreviewResult> captureProjectWebScreenshot(
  Workspace ws, {
  Duration buildTimeout = const Duration(minutes: 15),
}) async {
  final chrome = _findChrome();
  if (chrome == null) {
    return const WebPreviewResult(null, 'No Chrome/Edge found for screenshot.');
  }
  final mat = await const WorkspaceMaterializer().materialize(
    ws,
    tag: 'webpreview',
  );
  HttpServer? server;
  try {
    // The Flutter app is NOT necessarily at the materialized root — it commonly
    // lives in a subdir (e.g. `client/`, which is why CI does `cd client`). Build
    // in the directory that actually holds pubspec.yaml. Running `flutter create`
    // at a root WITHOUT a pubspec scaffolds a brand-new DEFAULT counter app and we
    // end up screenshotting THAT (the "Flutter Demo Home Page" false-negative that
    // reported a fully-built app as an empty starter template). If no pubspec
    // exists anywhere, there is no app to shoot — bail (best-effort null).
    final appDir = _findFlutterAppDir(mat.path);
    if (appDir == null) {
      return const WebPreviewResult(
        null,
        'No Flutter app (pubspec.yaml) found in the workspace — skipping shot.',
      );
    }
    // Configure web + build (adds the web/ shell if missing — never touches lib/).
    final build = await runCaptured(
      'flutter create . --platforms web && '
      'flutter pub get && '
      'flutter build web --release',
      workingDirectory: appDir,
      timeout: buildTimeout,
    );
    final webDir = Directory(
      '$appDir${Platform.pathSeparator}build'
      '${Platform.pathSeparator}web',
    );
    if (build.exitCode != 0 || !await webDir.exists()) {
      return WebPreviewResult(null, build.output);
    }

    // Serve the static build on a free loopback port.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    server.listen((req) => _serveStatic(req, webDir));

    // Headless screenshot. virtual-time-budget lets the Flutter bootstrap render
    // before the shot is taken.
    final shot = '${mat.path}${Platform.pathSeparator}shot.png';
    await Process.run(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--hide-scrollbars',
      '--window-size=1440,900',
      '--virtual-time-budget=12000',
      '--screenshot=$shot',
      'http://127.0.0.1:$port/',
    ]);
    final f = File(shot);
    final png = await f.exists() ? await f.readAsBytes() : null;
    return WebPreviewResult(png, build.output);
  } catch (e) {
    return WebPreviewResult(null, 'Screenshot failed: $e');
  } finally {
    await server?.close(force: true);
    await mat.dispose();
  }
}

Future<void> _serveStatic(HttpRequest req, Directory root) async {
  try {
    var rel = Uri.decodeComponent(req.uri.path);
    if (rel == '/' || rel.isEmpty) rel = '/index.html';
    var file = File('${root.path}${rel.replaceAll('/', Platform.pathSeparator)}');
    // SPA fallback: unknown non-asset paths → index.html.
    if (!await file.exists()) {
      file = File('${root.path}${Platform.pathSeparator}index.html');
    }
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    req.response.headers.contentType = _contentTypeFor(file.path);
    // Flutter web + CanvasKit want cross-origin isolation for some features; not
    // required for a static screenshot, so keep headers minimal.
    await req.response.addStream(file.openRead());
    await req.response.close();
  } catch (_) {
    try {
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    } catch (_) {}
  }
}

ContentType _contentTypeFor(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.html')) return ContentType.html;
  if (p.endsWith('.js') || p.endsWith('.mjs')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (p.endsWith('.json')) return ContentType('application', 'json');
  if (p.endsWith('.wasm')) return ContentType('application', 'wasm');
  if (p.endsWith('.css')) return ContentType('text', 'css');
  if (p.endsWith('.png')) return ContentType('image', 'png');
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (p.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (p.endsWith('.ttf')) return ContentType('font', 'ttf');
  if (p.endsWith('.otf')) return ContentType('font', 'otf');
  if (p.endsWith('.woff')) return ContentType('font', 'woff');
  if (p.endsWith('.woff2')) return ContentType('font', 'woff2');
  return ContentType.binary;
}

/// Locate the Flutter app's root inside the materialized tree: the SHALLOWEST
/// directory containing a `pubspec.yaml` (so a top-level app wins over any nested
/// `example/`; generated `build/` and `.dart_tool/` pubspecs are ignored). This
/// is what makes the web preview build the REAL app (often under `client/`)
/// instead of scaffolding a default counter app at an app-less root. Returns null
/// when the tree has no pubspec.yaml at all.
String? _findFlutterAppDir(String root) {
  String? best;
  var bestDepth = 1 << 30;
  final sep = Platform.pathSeparator;
  for (final e in Directory(root).listSync(recursive: true, followLinks: false)) {
    if (e is! File || e.uri.pathSegments.last != 'pubspec.yaml') continue;
    final rel = e.path.length > root.length ? e.path.substring(root.length) : '';
    if (rel.contains('${sep}build$sep') ||
        rel.contains('$sep.dart_tool$sep') ||
        rel.contains('${sep}node_modules$sep')) {
      continue;
    }
    final depth = rel.split(sep).where((s) => s.isNotEmpty).length;
    if (depth < bestDepth) {
      bestDepth = depth;
      best = e.parent.path;
    }
  }
  return best;
}

String? _findChrome() {
  final candidates = Platform.isWindows
      ? [
          r'C:\Program Files\Google\Chrome\Application\chrome.exe',
          r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
          r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
          r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        ]
      : Platform.isMacOS
      ? [
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
          '/Applications/Chromium.app/Contents/MacOS/Chromium',
        ]
      : ['/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}
