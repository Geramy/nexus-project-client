// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a workspace operation is refused (e.g. not found, name clash,
/// or — for the disk-backed implementation — a path that escapes the root).
class WorkspaceException implements Exception {
  final String message;
  WorkspaceException(this.message);
  @override
  String toString() => message;
}

/// One node in the workspace tree.
class FileEntry {
  /// Basename, e.g. `main.dart`.
  final String name;

  /// Workspace-relative POSIX path with a leading slash, e.g. `/src/main.dart`.
  /// `/` is the workspace root.
  final String path;
  final bool isDirectory;
  final bool isLink;
  final int size;
  final DateTime modified;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isLink = false,
    required this.size,
    required this.modified,
  });

  /// Parent directory's workspace path (`/` for root-level entries).
  String get parent {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }
}

/// A project's workspace: a tree of files/folders addressed by POSIX paths
/// ("/" is the root). Implementations:
///   - [VhdWorkspace]  — single SQLite file ("virtual disk"), accessed purely
///     through this API (no mounting). The git engine binds to the same file.
///   - WorkspaceFs     — a real host directory (used for native import/export).
///
/// All paths are workspace-relative; callers never see host paths.
abstract interface class Workspace {
  /// Does a file or directory exist at [wsPath]?
  Future<bool> exists(String wsPath);

  /// Metadata for one node. Throws if not found.
  Future<FileEntry> stat(String wsPath);

  /// Immediate children of a directory (default: root), dirs-first then by name.
  Future<List<FileEntry>> list([String wsPath = '/']);

  /// Recursive depth-first walk, capped at [maxEntries].
  Future<List<FileEntry>> walk({String from = '/', int maxEntries = 5000});

  Future<String> readString(String wsPath);
  Future<Uint8List> readBytes(String wsPath);

  /// Random-access slice read — bytes [offset, offset+length) — without loading
  /// the whole file. This is the "start/end byte" seek over the single file.
  Future<Uint8List> readRange(String wsPath, int offset, int length);

  /// Heuristic binary sniff (NUL byte in the first few KB).
  Future<bool> isProbablyBinary(String wsPath);

  Future<FileEntry> writeString(String wsPath, String content);
  Future<FileEntry> writeBytes(String wsPath, List<int> bytes);

  Future<FileEntry> createDirectory(String wsPath);
  Future<FileEntry> createFile(String wsPath, {bool overwrite = false});

  Future<void> delete(String wsPath, {bool recursive = true});
  Future<FileEntry> move(String fromWs, String toWs);
  Future<FileEntry> copy(String fromWs, String toWs);

  /// Total bytes + file count, for status display.
  Future<({int bytes, int files})> usage();
}

/// Normalize a caller path to a clean relative form (POSIX, no leading slash,
/// `.`/empty -> ''). Shared by implementations.
String normalizeRel(String wsPath) {
  var s = wsPath.replaceAll('\\', '/').trim();
  while (s.startsWith('/')) {
    s = s.substring(1);
  }
  if (s == '.' || s.isEmpty) return '';
  // Collapse '.' and '..' segments lexically.
  final out = <String>[];
  for (final seg in s.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(seg);
  }
  return out.join('/');
}

/// Split a normalized relative path into segments ('' -> []).
List<String> pathSegments(String wsPath) {
  final rel = normalizeRel(wsPath);
  return rel.isEmpty ? const [] : rel.split('/');
}

/// Pretty-print a byte count.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}

/// UTF-8 decode bytes leniently (used by viewers).
String decodeUtf8Lossy(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);
