// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:git2dart_binaries/git2dart_binaries.dart';

/// Creates the git tables inside a `.nxtprj` SQLite database. Git objects and
/// refs live in the SAME single file as the workspace filesystem.
void initGitSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS git_objects(
      oid    TEXT PRIMARY KEY,   -- 40-hex SHA-1
      otype  INTEGER NOT NULL,   -- git_object_t
      size   INTEGER NOT NULL,   -- raw (inflated) content length
      data   BLOB NOT NULL       -- raw object content (libgit2 handles framing)
    );
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS git_refs(
      name      TEXT PRIMARY KEY, -- e.g. refs/heads/main, HEAD
      target    TEXT,             -- 40-hex oid for direct refs
      symbolic  TEXT              -- target ref name for symbolic refs
    );
  ''');
}

/// A custom libgit2 **ODB backend** that stores git objects in the project's
/// `.nxtprj` SQLite file.
///
/// libgit2 invokes the callbacks *synchronously* on the calling thread, and
/// `NativeCallable.isolateLocal` requires same-isolate invocation — so every
/// libgit2 call (and this [db] handle) MUST live on one isolate. The callbacks
/// close over [db]; their `NativeCallable`s are retained for the backend's life.
class NxtprjGitOdb {
  final Database db;
  final List<NativeCallable> _callables = [];
  Pointer<git_odb_backend>? _backend;

  NxtprjGitOdb(this.db);

  /// Build a `git_odb` populated with this SQLite-backed backend, ready to hand
  /// to `git_repository_set_odb`.
  Pointer<git_odb> createOdb() {
    final be = calloc<git_odb_backend>();
    be.ref.version = GIT_ODB_BACKEND_VERSION;

    final readCb =
        NativeCallable<
          Int Function(
            Pointer<Pointer<Void>>,
            Pointer<Size>,
            Pointer<Int>,
            Pointer<git_odb_backend>,
            Pointer<git_oid>,
          )
        >.isolateLocal(_read, exceptionalReturn: -1);
    final readHeaderCb =
        NativeCallable<
          Int Function(
            Pointer<Size>,
            Pointer<Int>,
            Pointer<git_odb_backend>,
            Pointer<git_oid>,
          )
        >.isolateLocal(_readHeader, exceptionalReturn: -1);
    final existsCb =
        NativeCallable<
          Int Function(Pointer<git_odb_backend>, Pointer<git_oid>)
        >.isolateLocal(_exists, exceptionalReturn: 0);
    final writeCb =
        NativeCallable<
          Int Function(
            Pointer<git_odb_backend>,
            Pointer<git_oid>,
            Pointer<Void>,
            Size,
            Int,
          )
        >.isolateLocal(_write, exceptionalReturn: -1);
    final freeCb =
        NativeCallable<Void Function(Pointer<git_odb_backend>)>.isolateLocal(
          _free,
        );

    _callables.addAll([readCb, readHeaderCb, existsCb, writeCb, freeCb]);
    be.ref.read = readCb.nativeFunction;
    be.ref.read_header = readHeaderCb.nativeFunction;
    be.ref.exists = existsCb.nativeFunction;
    be.ref.write = writeCb.nativeFunction;
    be.ref.free = freeCb.nativeFunction;
    _backend = be;

    final odbOut = calloc<Pointer<git_odb>>();
    try {
      final rc = libgit2.git_odb_new(odbOut, nullptr);
      if (rc != 0) throw StateError('git_odb_new failed ($rc)');
      final odb = odbOut.value;
      final rc2 = libgit2.git_odb_add_backend(odb, be.cast(), 100);
      if (rc2 != 0) throw StateError('git_odb_add_backend failed ($rc2)');
      return odb;
    } finally {
      calloc.free(odbOut);
    }
  }

  void dispose() {
    for (final c in _callables) {
      c.close();
    }
    _callables.clear();
    final be = _backend;
    if (be != null) {
      calloc.free(be);
      _backend = null;
    }
  }

  /// 40-char hex of a SHA-1 oid.
  String _hex(Pointer<git_oid> oid) {
    final b = StringBuffer();
    for (var i = 0; i < 20; i++) {
      b.write(oid.ref.id[i].toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  // ── ODB callbacks (run synchronously from libgit2) ───────────────────

  int _read(
    Pointer<Pointer<Void>> outBuf,
    Pointer<Size> outLen,
    Pointer<Int> outType,
    Pointer<git_odb_backend> be,
    Pointer<git_oid> oid,
  ) {
    final rows = db.select(
      'SELECT otype, size, data FROM git_objects WHERE oid=?',
      [_hex(oid)],
    );
    if (rows.isEmpty) return -3; // GIT_ENOTFOUND
    final data = rows.first['data'] as Uint8List;
    // Buffer MUST be allocated by libgit2 so it can free it later.
    final buf = libgit2.git_odb_backend_data_alloc(be, data.length);
    if (buf == nullptr) return -1;
    buf.cast<Uint8>().asTypedList(data.length).setAll(0, data);
    outBuf.value = buf;
    outLen.value = data.length;
    outType.value = rows.first['otype'] as int;
    return 0;
  }

  int _readHeader(
    Pointer<Size> outLen,
    Pointer<Int> outType,
    Pointer<git_odb_backend> be,
    Pointer<git_oid> oid,
  ) {
    final rows = db.select('SELECT otype, size FROM git_objects WHERE oid=?', [
      _hex(oid),
    ]);
    if (rows.isEmpty) return -3;
    outLen.value = rows.first['size'] as int;
    outType.value = rows.first['otype'] as int;
    return 0;
  }

  int _exists(Pointer<git_odb_backend> be, Pointer<git_oid> oid) {
    return db.select('SELECT 1 FROM git_objects WHERE oid=?', [
          _hex(oid),
        ]).isEmpty
        ? 0
        : 1;
  }

  int _write(
    Pointer<git_odb_backend> be,
    Pointer<git_oid> oid,
    Pointer<Void> data,
    int len,
    int type,
  ) {
    final bytes = Uint8List.fromList(data.cast<Uint8>().asTypedList(len));
    db.execute(
      'INSERT OR REPLACE INTO git_objects(oid, otype, size, data) VALUES(?,?,?,?)',
      [_hex(oid), type, len, bytes],
    );
    return 0;
  }

  void _free(Pointer<git_odb_backend> be) {
    // The backend struct is freed in dispose(); nothing to do per-call.
  }
}
