// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:typed_data';

import 'git/nxtprj_git_engine.dart';
import 'workspace.dart';

/// A READ-ONLY [Workspace] view of a single git branch's tip, served straight
/// from the object DB (no checkout, no working-tree mutation). This lets the
/// Code browser show an in-progress task's `task/<id>` branch — the agent's
/// committed work — without disturbing the live workspace the orchestrator is
/// editing. Every mutating method throws; the tree and editor render it exactly
/// like a normal workspace.
class GitBranchWorkspace implements Workspace {
  final NxtprjGitEngine _engine;
  final String branch;

  /// path→blobOid for the branch tip (relative, no leading slash), captured once
  /// at construction (snapshot semantics).
  final Map<String, String> _files;

  GitBranchWorkspace(this._engine, this.branch, Map<String, String> files)
    : _files = files;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  Never _readOnly() => throw WorkspaceException(
    'Read-only view of branch "$branch" — switch back to the live workspace to edit.',
  );

  /// All directory paths (relative, no leading slash) implied by the file set.
  Set<String> _dirs() {
    final dirs = <String>{};
    for (final rel in _files.keys) {
      final segs = rel.split('/');
      for (var i = 1; i < segs.length; i++) {
        dirs.add(segs.sublist(0, i).join('/'));
      }
    }
    return dirs;
  }

  FileEntry _fileEntry(String rel, int size) => FileEntry(
    name: rel.contains('/') ? rel.substring(rel.lastIndexOf('/') + 1) : rel,
    path: '/$rel',
    isDirectory: false,
    size: size,
    modified: _epoch,
  );

  FileEntry _dirEntry(String rel) => FileEntry(
    name: rel.contains('/') ? rel.substring(rel.lastIndexOf('/') + 1) : rel,
    path: '/$rel',
    isDirectory: true,
    size: 0,
    modified: _epoch,
  );

  @override
  Future<bool> exists(String wsPath) async {
    final rel = normalizeRel(wsPath);
    if (rel.isEmpty) return true; // root
    if (_files.containsKey(rel)) return true;
    return _files.keys.any((p) => p.startsWith('$rel/'));
  }

  @override
  Future<FileEntry> stat(String wsPath) async {
    final rel = normalizeRel(wsPath);
    if (rel.isEmpty) return _dirEntry('');
    final oid = _files[rel];
    if (oid != null) return _fileEntry(rel, _engine.blobBytesByOid(oid).length);
    if (_files.keys.any((p) => p.startsWith('$rel/'))) return _dirEntry(rel);
    throw WorkspaceException('Not found: $wsPath');
  }

  @override
  Future<List<FileEntry>> list([String wsPath = '/']) async {
    final base = normalizeRel(wsPath);
    final prefix = base.isEmpty ? '' : '$base/';
    final seenDirs = <String>{};
    final out = <FileEntry>[];
    for (final rel in _files.keys) {
      if (!rel.startsWith(prefix)) continue;
      final rest = rel.substring(prefix.length);
      if (rest.isEmpty) continue;
      final slash = rest.indexOf('/');
      if (slash < 0) {
        out.add(_fileEntry(rel, _engine.blobBytesByOid(_files[rel]!).length));
      } else {
        final dirRel = '$prefix${rest.substring(0, slash)}';
        if (seenDirs.add(dirRel)) out.add(_dirEntry(dirRel));
      }
    }
    out.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Future<List<FileEntry>> walk({String from = '/', int maxEntries = 5000}) async {
    final base = normalizeRel(from);
    final prefix = base.isEmpty ? '' : '$base/';
    final out = <FileEntry>[];
    for (final dir in _dirs()) {
      if (base.isEmpty || dir == base || dir.startsWith(prefix)) {
        out.add(_dirEntry(dir));
      }
    }
    for (final entry in _files.entries) {
      final rel = entry.key;
      if (base.isNotEmpty && rel != base && !rel.startsWith(prefix)) continue;
      out.add(_fileEntry(rel, _engine.blobBytesByOid(entry.value).length));
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out.length > maxEntries ? out.sublist(0, maxEntries) : out;
  }

  @override
  Future<Uint8List> readBytes(String wsPath) async {
    final rel = normalizeRel(wsPath);
    final oid = _files[rel];
    if (oid == null) throw WorkspaceException('Not found: $wsPath');
    return _engine.blobBytesByOid(oid);
  }

  @override
  Future<String> readString(String wsPath) async =>
      decodeUtf8Lossy(await readBytes(wsPath));

  @override
  Future<Uint8List> readRange(String wsPath, int offset, int length) async {
    final bytes = await readBytes(wsPath);
    final start = offset.clamp(0, bytes.length);
    final end = (offset + length).clamp(start, bytes.length);
    return Uint8List.sublistView(bytes, start, end);
  }

  @override
  Future<bool> isProbablyBinary(String wsPath) async {
    final bytes = await readBytes(wsPath);
    final n = bytes.length < 8192 ? bytes.length : 8192;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  @override
  Future<({int bytes, int files})> usage() async {
    var total = 0;
    for (final oid in _files.values) {
      total += _engine.blobBytesByOid(oid).length;
    }
    return (bytes: total, files: _files.length);
  }

  // ── Mutations are refused — this is a read-only snapshot. ────────────────
  @override
  Future<FileEntry> writeString(String wsPath, String content) => _readOnly();
  @override
  Future<FileEntry> writeBytes(String wsPath, List<int> bytes) => _readOnly();
  @override
  Future<FileEntry> createDirectory(String wsPath) => _readOnly();
  @override
  Future<FileEntry> createFile(String wsPath, {bool overwrite = false}) =>
      _readOnly();
  @override
  Future<void> delete(String wsPath, {bool recursive = true}) => _readOnly();
  @override
  Future<FileEntry> move(String fromWs, String toWs) => _readOnly();
  @override
  Future<FileEntry> copy(String fromWs, String toWs) => _readOnly();
}
