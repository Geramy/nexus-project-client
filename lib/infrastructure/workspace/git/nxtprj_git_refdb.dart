// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:git2dart_binaries/git2dart_binaries.dart';

/// Per-iterator cursor state, kept on the Dart side and keyed by the address of
/// the native [git_reference_iterator] struct (libgit2 hands us back the same
/// pointer on every `next`/`next_name`/`free` call).
class _RefIterState {
  final List<String> names;
  int pos = 0;
  // Owned native string returned by the most recent `next_name`; freed on the
  // following call / on free so the caller can read it in the meantime.
  Pointer<Char> lastName = nullptr;
  _RefIterState(this.names);
}

/// A custom libgit2 **refdb backend** that stores git references in the
/// project's `.nxtprj` SQLite file (the `git_refs` table created by
/// `initGitSchema`).
///
/// libgit2 invokes the callbacks *synchronously* on the calling thread, and
/// `NativeCallable.isolateLocal` requires same-isolate invocation — so every
/// libgit2 call (and this [db] handle) MUST live on one isolate. The callbacks
/// close over [db]; their `NativeCallable`s are retained for the backend's life.
class NxtprjGitRefdb {
  final Database db;
  final List<NativeCallable> _callables = [];
  Pointer<git_refdb_backend>? _backend;

  // Iterator native callables + the live iterator state, keyed by struct addr.
  final Map<int, _RefIterState> _iters = {};
  NativeCallable<
      Int Function(Pointer<Pointer<git_reference>>,
          Pointer<git_reference_iterator>)>? _iterNextCb;
  NativeCallable<
      Int Function(Pointer<Pointer<Char>>,
          Pointer<git_reference_iterator>)>? _iterNextNameCb;
  NativeCallable<Void Function(Pointer<git_reference_iterator>)>? _iterFreeCb;

  NxtprjGitRefdb(this.db);

  /// Build a `git_refdb` populated with this SQLite-backed backend, ready to
  /// hand to `git_repository_set_refdb`.
  ///
  /// [repo] is required because `git_refdb_new` takes the owning repository.
  Pointer<git_refdb> createRefdb(Pointer<git_repository> repo) {
    final be = calloc<git_refdb_backend>();
    final initRc = libgit2.git_refdb_init_backend(be, GIT_REFDB_BACKEND_VERSION);
    if (initRc != 0) {
      calloc.free(be);
      throw StateError('git_refdb_init_backend failed ($initRc)');
    }

    final existsCb = NativeCallable<
        Int Function(Pointer<Int>, Pointer<git_refdb_backend>,
            Pointer<Char>)>.isolateLocal(_exists, exceptionalReturn: -1);
    final lookupCb = NativeCallable<
            Int Function(Pointer<Pointer<git_reference>>,
                Pointer<git_refdb_backend>, Pointer<Char>)>.isolateLocal(_lookup,
        exceptionalReturn: -1);
    final iteratorCb = NativeCallable<
            Int Function(Pointer<Pointer<git_reference_iterator>>,
                Pointer<git_refdb_backend>, Pointer<Char>)>.isolateLocal(
        _iterator,
        exceptionalReturn: -1);
    final writeCb = NativeCallable<
        Int Function(
            Pointer<git_refdb_backend>,
            Pointer<git_reference>,
            Int,
            Pointer<git_signature>,
            Pointer<Char>,
            Pointer<git_oid>,
            Pointer<Char>)>.isolateLocal(_write, exceptionalReturn: -1);
    final delCb = NativeCallable<
        Int Function(Pointer<git_refdb_backend>, Pointer<Char>,
            Pointer<git_oid>, Pointer<Char>)>.isolateLocal(_del,
        exceptionalReturn: -1);
    final hasLogCb = NativeCallable<
        Int Function(Pointer<git_refdb_backend>,
            Pointer<Char>)>.isolateLocal(_hasLog, exceptionalReturn: 0);
    final ensureLogCb = NativeCallable<
        Int Function(Pointer<git_refdb_backend>,
            Pointer<Char>)>.isolateLocal(_ensureLog, exceptionalReturn: 0);
    final freeCb =
        NativeCallable<Void Function(Pointer<git_refdb_backend>)>.isolateLocal(
            _free);
    // libgit2 1.9's git_refdb_set_backend validates rename/lock/unlock are
    // non-null (returns GIT_EINVALID otherwise). Our basic commit/status flow
    // never calls rename, and single-isolate use needs no real locking — so
    // these are minimal no-op stubs that satisfy validation cleanly.
    final renameCb = NativeCallable<
        Int Function(
            Pointer<Pointer<git_reference>>,
            Pointer<git_refdb_backend>,
            Pointer<Char>,
            Pointer<Char>,
            Int,
            Pointer<git_signature>,
            Pointer<Char>)>.isolateLocal(_rename, exceptionalReturn: -1);
    final lockCb = NativeCallable<
        Int Function(
            Pointer<Pointer<Void>>,
            Pointer<git_refdb_backend>,
            Pointer<Char>)>.isolateLocal(_lock, exceptionalReturn: 0);
    final unlockCb = NativeCallable<
        Int Function(
            Pointer<git_refdb_backend>,
            Pointer<Void>,
            Int,
            Int,
            Pointer<git_reference>,
            Pointer<git_signature>,
            Pointer<Char>)>.isolateLocal(_unlock, exceptionalReturn: 0);
    // libgit2's git_refdb_set_backend also validates that ALL four reflog_*
    // callbacks are non-null (they are documented as "must provide"). We don't
    // maintain a reflog, so these are no-op stubs that pair with has_log
    // returning 0 above.
    final reflogReadCb = NativeCallable<
        Int Function(Pointer<Pointer<git_reflog>>,
            Pointer<git_refdb_backend>, Pointer<Char>)>.isolateLocal(_reflogRead, exceptionalReturn: -3);
    final reflogWriteCb = NativeCallable<
        Int Function(Pointer<git_refdb_backend>,
            Pointer<git_reflog>)>.isolateLocal(_reflogWrite, exceptionalReturn: 0);
    final reflogRenameCb = NativeCallable<
        Int Function(Pointer<git_refdb_backend>, Pointer<Char>,
            Pointer<Char>)>.isolateLocal(_reflogRename, exceptionalReturn: 0);
    final reflogDeleteCb = NativeCallable<
        Int Function(Pointer<git_refdb_backend>,
            Pointer<Char>)>.isolateLocal(_reflogDelete, exceptionalReturn: 0);

    // Iterator sub-callbacks (shared across all iterators, dispatched by addr).
    _iterNextCb = NativeCallable<
        Int Function(Pointer<Pointer<git_reference>>,
            Pointer<git_reference_iterator>)>.isolateLocal(_iterNext,
        exceptionalReturn: -1);
    _iterNextNameCb = NativeCallable<
        Int Function(Pointer<Pointer<Char>>,
            Pointer<git_reference_iterator>)>.isolateLocal(_iterNextName,
        exceptionalReturn: -1);
    _iterFreeCb =
        NativeCallable<Void Function(Pointer<git_reference_iterator>)>
            .isolateLocal(_iterFree);

    _callables.addAll([
      existsCb,
      lookupCb,
      iteratorCb,
      writeCb,
      delCb,
      hasLogCb,
      ensureLogCb,
      freeCb,
      renameCb,
      lockCb,
      unlockCb,
      reflogReadCb,
      reflogWriteCb,
      reflogRenameCb,
      reflogDeleteCb,
      _iterNextCb!,
      _iterNextNameCb!,
      _iterFreeCb!,
    ]);

    be.ref.exists = existsCb.nativeFunction;
    be.ref.lookup = lookupCb.nativeFunction;
    be.ref.iterator = iteratorCb.nativeFunction;
    be.ref.write = writeCb.nativeFunction;
    be.ref.del = delCb.nativeFunction;
    be.ref.has_log = hasLogCb.nativeFunction;
    be.ref.ensure_log = ensureLogCb.nativeFunction;
    be.ref.rename = renameCb.nativeFunction;
    be.ref.lock = lockCb.nativeFunction;
    be.ref.unlock = unlockCb.nativeFunction;
    be.ref.reflog_read = reflogReadCb.nativeFunction;
    be.ref.reflog_write = reflogWriteCb.nativeFunction;
    be.ref.reflog_rename = reflogRenameCb.nativeFunction;
    be.ref.reflog_delete = reflogDeleteCb.nativeFunction;
    be.ref.free = freeCb.nativeFunction;
    _backend = be;

    final refdbOut = calloc<Pointer<git_refdb>>();
    try {
      final rc = libgit2.git_refdb_new(refdbOut, repo);
      if (rc != 0) throw StateError('git_refdb_new failed ($rc)');
      final refdb = refdbOut.value;
      final rc2 = libgit2.git_refdb_set_backend(refdb, be);
      if (rc2 != 0) throw StateError('git_refdb_set_backend failed ($rc2)');
      return refdb;
    } finally {
      calloc.free(refdbOut);
    }
  }

  void dispose() {
    // Free any iterator state / leftover native strings.
    for (final st in _iters.values) {
      if (st.lastName != nullptr) calloc.free(st.lastName);
    }
    _iters.clear();
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

  // ── helpers ──────────────────────────────────────────────────────────

  /// Builds a `git_oid` from a 40-char hex string. Caller owns the returned
  /// pointer and must `calloc.free` it.
  Pointer<git_oid> _oidFromHex(String hex) {
    final oid = calloc<git_oid>();
    final cstr = hex.toNativeUtf8();
    try {
      libgit2.git_oid_fromstr(oid, cstr.cast(), git_oid_t.GIT_OID_SHA1);
    } finally {
      calloc.free(cstr);
    }
    return oid;
  }

  /// 40-char hex of a SHA-1 oid.
  String _hex(Pointer<git_oid> oid) {
    final b = StringBuffer();
    for (var i = 0; i < 20; i++) {
      b.write(oid.ref.id[i].toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  /// Allocates a `git_reference` for the stored row. Returns `nullptr` on
  /// failure. libgit2 copies the name + oid, so the temporaries are freed here.
  Pointer<git_reference> _allocRef(String name, String? target, String? symbolic) {
    final namePtr = name.toNativeUtf8();
    try {
      if (symbolic != null && symbolic.isNotEmpty) {
        final symPtr = symbolic.toNativeUtf8();
        try {
          return libgit2.git_reference__alloc_symbolic(
              namePtr.cast(), symPtr.cast());
        } finally {
          calloc.free(symPtr);
        }
      }
      if (target != null && target.isNotEmpty) {
        final oid = _oidFromHex(target);
        try {
          return libgit2.git_reference__alloc(namePtr.cast(), oid, nullptr);
        } finally {
          calloc.free(oid);
        }
      }
      return nullptr;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Reads all ref names matching [glob]. A trailing `*` (or an empty/null
  /// glob) is treated as a prefix match; otherwise an exact match.
  List<String> _matchingNames(String? glob) {
    if (glob == null || glob.isEmpty || glob == '*') {
      return db
          .select('SELECT name FROM git_refs ORDER BY name')
          .map((r) => r['name'] as String)
          .toList();
    }
    if (glob.endsWith('*')) {
      final prefix = glob.substring(0, glob.length - 1);
      return db
          .select('SELECT name FROM git_refs WHERE name LIKE ? ORDER BY name',
              ['${_escapeLike(prefix)}%'])
          .map((r) => r['name'] as String)
          .toList();
    }
    return db
        .select('SELECT name FROM git_refs WHERE name = ?', [glob])
        .map((r) => r['name'] as String)
        .toList();
  }

  String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  // ── refdb callbacks (run synchronously from libgit2) ─────────────────

  int _exists(Pointer<Int> existsOut, Pointer<git_refdb_backend> be,
      Pointer<Char> refName) {
    final name = refName.cast<Utf8>().toDartString();
    final found =
        db.select('SELECT 1 FROM git_refs WHERE name = ?', [name]).isNotEmpty;
    existsOut.value = found ? 1 : 0;
    return 0;
  }

  int _lookup(Pointer<Pointer<git_reference>> out,
      Pointer<git_refdb_backend> be, Pointer<Char> refName) {
    final name = refName.cast<Utf8>().toDartString();
    final rows =
        db.select('SELECT target, symbolic FROM git_refs WHERE name = ?', [name]);
    if (rows.isEmpty) {
      out.value = nullptr;
      return -3; // GIT_ENOTFOUND
    }
    final ref = _allocRef(
        name, rows.first['target'] as String?, rows.first['symbolic'] as String?);
    if (ref == nullptr) {
      out.value = nullptr;
      return -1;
    }
    out.value = ref;
    return 0;
  }

  int _iterator(Pointer<Pointer<git_reference_iterator>> iterOut,
      Pointer<git_refdb_backend> be, Pointer<Char> glob) {
    final globStr = glob == nullptr ? null : glob.cast<Utf8>().toDartString();
    final names = _matchingNames(globStr);

    final iter = calloc<git_reference_iterator>();
    iter.ref.next = _iterNextCb!.nativeFunction;
    iter.ref.next_name = _iterNextNameCb!.nativeFunction;
    iter.ref.free = _iterFreeCb!.nativeFunction;
    _iters[iter.address] = _RefIterState(names);
    iterOut.value = iter;
    return 0;
  }

  int _iterNext(
      Pointer<Pointer<git_reference>> out, Pointer<git_reference_iterator> iter) {
    final st = _iters[iter.address];
    if (st == null) {
      out.value = nullptr;
      return -31; // GIT_ITEROVER
    }
    while (st.pos < st.names.length) {
      final name = st.names[st.pos++];
      final rows = db
          .select('SELECT target, symbolic FROM git_refs WHERE name = ?', [name]);
      if (rows.isEmpty) continue; // Row vanished mid-iteration; skip it.
      final ref = _allocRef(name, rows.first['target'] as String?,
          rows.first['symbolic'] as String?);
      if (ref == nullptr) {
        out.value = nullptr;
        return -1;
      }
      out.value = ref;
      return 0;
    }
    out.value = nullptr;
    return -31; // GIT_ITEROVER
  }

  int _iterNextName(
      Pointer<Pointer<Char>> out, Pointer<git_reference_iterator> iter) {
    final st = _iters[iter.address];
    if (st == null || st.pos >= st.names.length) {
      out.value = nullptr;
      return -31; // GIT_ITEROVER
    }
    // Release the previously returned name (caller has consumed it by now).
    if (st.lastName != nullptr) {
      calloc.free(st.lastName);
      st.lastName = nullptr;
    }
    final namePtr = st.names[st.pos++].toNativeUtf8().cast<Char>();
    st.lastName = namePtr;
    out.value = namePtr;
    return 0;
  }

  void _iterFree(Pointer<git_reference_iterator> iter) {
    final st = _iters.remove(iter.address);
    if (st != null && st.lastName != nullptr) {
      calloc.free(st.lastName);
    }
    calloc.free(iter);
  }

  int _write(
      Pointer<git_refdb_backend> be,
      Pointer<git_reference> ref,
      int force,
      Pointer<git_signature> who,
      Pointer<Char> message,
      Pointer<git_oid> old,
      Pointer<Char> oldTarget) {
    final namePtr = libgit2.git_reference_name(ref);
    if (namePtr == nullptr) return -1;
    final name = namePtr.cast<Utf8>().toDartString();

    final refType = libgit2.git_reference_type(ref);
    // GIT_REFERENCE_SYMBOLIC == 2, GIT_REFERENCE_DIRECT == 1.
    if (refType == git_reference_t.GIT_REFERENCE_SYMBOLIC) {
      final symPtr = libgit2.git_reference_symbolic_target(ref);
      final sym = symPtr == nullptr ? null : symPtr.cast<Utf8>().toDartString();
      db.execute(
          'INSERT OR REPLACE INTO git_refs(name, target, symbolic) VALUES(?, NULL, ?)',
          [name, sym]);
    } else {
      final oidPtr = libgit2.git_reference_target(ref);
      if (oidPtr == nullptr) return -1;
      db.execute(
          'INSERT OR REPLACE INTO git_refs(name, target, symbolic) VALUES(?, ?, NULL)',
          [name, _hex(oidPtr)]);
    }
    return 0;
  }

  int _del(Pointer<git_refdb_backend> be, Pointer<Char> refName,
      Pointer<git_oid> oldId, Pointer<Char> oldTarget) {
    final name = refName.cast<Utf8>().toDartString();
    db.execute('DELETE FROM git_refs WHERE name = ?', [name]);
    return 0;
  }

  int _hasLog(Pointer<git_refdb_backend> be, Pointer<Char> refName) {
    // No reflog support.
    return 0;
  }

  int _ensureLog(Pointer<git_refdb_backend> be, Pointer<Char> refName) {
    // No reflog support; report success so ref writes are not blocked.
    return 0;
  }

  void _free(Pointer<git_refdb_backend> be) {
    // The backend struct is freed in dispose(); nothing to do per-call.
  }

  // ── Minimal stubs to satisfy git_refdb_set_backend validation ─────

  /// Rename callback. libgit2 1.9 requires this pointer to be non-null but our
  /// commit/status flow never calls rename — branch ops would. For now we
  /// report GIT_ENOTFOUND so any unexpected caller fails loudly rather than
  /// silently believing the rename succeeded. Out is cleared.
  int _rename(
      Pointer<Pointer<git_reference>> outRef,
      Pointer<git_refdb_backend> be,
      Pointer<Char> oldName,
      Pointer<Char> newName,
      int force,
      Pointer<git_signature> who,
      Pointer<Char> message) {
    outRef.value = nullptr;
    return -3; // GIT_ENOTFOUND
  }

  /// Lock callback. Single-isolate, single SQLite connection: no real locking
  /// needed. Returns 0 with a null payload (passed back to [_unlock]).
  int _lock(Pointer<Pointer<Void>> payloadOut,
      Pointer<git_refdb_backend> be, Pointer<Char> refName) {
    payloadOut.value = nullptr;
    return 0;
  }

  /// Unlock callback. No-op (see [_lock]).
  int _unlock(
      Pointer<git_refdb_backend> be,
      Pointer<Void> payload,
      int success,
      int updateReflog,
      Pointer<git_reference> ref,
      Pointer<git_signature> sig,
      Pointer<Char> message) {
    return 0;
  }

  /// Reflog read. We don't maintain a reflog → not found.
  int _reflogRead(Pointer<Pointer<git_reflog>> out,
      Pointer<git_refdb_backend> be, Pointer<Char> name) {
    out.value = nullptr;
    return -3; // GIT_ENOTFOUND
  }

  /// Reflog write. No-op success — pairs with has_log returning 0.
  int _reflogWrite(Pointer<git_refdb_backend> be, Pointer<git_reflog> reflog) => 0;

  /// Reflog rename. No-op success.
  int _reflogRename(Pointer<git_refdb_backend> be,
      Pointer<Char> oldName, Pointer<Char> newName) => 0;

  /// Reflog delete. No-op success.
  int _reflogDelete(Pointer<git_refdb_backend> be, Pointer<Char> name) => 0;
}
