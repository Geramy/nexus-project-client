// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../workspace/workspace.dart';

/// Builds the tar archive that the Docker Engine API's `POST /build` expects as
/// its request body. The daemon reads the Dockerfile and every other build
/// context file straight out of this tar — no host filesystem is touched, which
/// keeps the whole flow inside the macOS App Sandbox.
class DockerContextTar {
  const DockerContextTar();

  /// Pack every file under [from] in [ws] into an (uncompressed) tar. Entry
  /// names are workspace-relative POSIX paths WITHOUT a leading slash, which is
  /// what Docker expects (e.g. `Dockerfile`, `src/main.dart`).
  Future<Uint8List> fromWorkspace(
    Workspace ws, {
    String from = '/',
    int maxEntries = 20000,
  }) async {
    final archive = Archive();
    final entries = await ws.walk(from: from, maxEntries: maxEntries);
    final fromRel = normalizeRel(from);

    for (final e in entries) {
      if (e.isDirectory) continue;
      final rel = _relativeTo(e.path, fromRel);
      if (rel.isEmpty) continue;
      final bytes = await ws.readBytes(e.path);
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    }

    final encoded = TarEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  String _relativeTo(String wsPath, String fromRel) {
    final rel = normalizeRel(wsPath);
    if (fromRel.isEmpty) return rel;
    if (rel == fromRel) return '';
    final prefix = '$fromRel/';
    return rel.startsWith(prefix) ? rel.substring(prefix.length) : rel;
  }
}
