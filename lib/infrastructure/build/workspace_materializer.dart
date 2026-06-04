// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../workspace/workspace.dart';

/// A materialized copy of a project's virtual workspace on the real filesystem.
/// Holds the host [dir] the files were written into; call [dispose] to delete it
/// when the build/CI run that needed it finishes.
class MaterializedWorkspace {
  final Directory dir;
  final int fileCount;
  const MaterializedWorkspace(this.dir, this.fileCount);

  String get path => dir.path;

  Future<void> dispose() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; a leftover temp dir is harmless.
    }
  }
}

/// Exports a project's [Workspace] (the SQLite virtual disk) into a real
/// temporary directory so external tools — `docker build`, the local CI runner —
/// can read actual files. Nothing else in the app touches the host filesystem
/// for project content; this is the bridge.
class WorkspaceMaterializer {
  const WorkspaceMaterializer();

  /// Write every file under [from] in [ws] into a fresh temp directory and
  /// return a handle to it. The directory lives under the OS temp area in a
  /// `nexus_build_<tag>_<ts>` folder. Caller MUST call [MaterializedWorkspace.dispose].
  ///
  /// [maxEntries] caps the walk (defensive against pathological trees).
  Future<MaterializedWorkspace> materialize(
    Workspace ws, {
    String from = '/',
    String tag = 'ws',
    int maxEntries = 20000,
  }) async {
    final base = await getTemporaryDirectory();
    final safeTag = tag.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final root = Directory(
      p.join(
        base.path,
        'nexus_build_${safeTag}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await root.create(recursive: true);

    final entries = await ws.walk(from: from, maxEntries: maxEntries);
    final fromRel = normalizeRel(from);
    var count = 0;
    for (final e in entries) {
      if (e.isDirectory) continue;
      final rel = _relativeTo(e.path, fromRel);
      if (rel.isEmpty) continue;
      final hostPath = p.join(root.path, p.joinAll(rel.split('/')));
      final f = File(hostPath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(await ws.readBytes(e.path));
      count++;
    }
    return MaterializedWorkspace(root, count);
  }

  /// Strip the [fromRel] prefix off a workspace path, returning a clean relative
  /// path (no leading slash). `/src/main.dart` with from `/` → `src/main.dart`;
  /// `/sub/a.txt` with from `/sub` → `a.txt`.
  String _relativeTo(String wsPath, String fromRel) {
    final rel = normalizeRel(wsPath);
    if (fromRel.isEmpty) return rel;
    if (rel == fromRel) return '';
    final prefix = '$fromRel/';
    return rel.startsWith(prefix) ? rel.substring(prefix.length) : rel;
  }
}
