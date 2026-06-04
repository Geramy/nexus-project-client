// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';

/// A minimal FIFO async mutex: [run] serializes its callbacks so only one runs
/// at a time, in call order. Used as the per-project "git lane" so concurrent
/// task agents never interleave multi-step libgit2 + SQLite operations on the
/// single shared object/ref database (which is single-isolate by design).
///
/// A callback that throws still releases the lock (the next waiter proceeds),
/// and the error propagates to that caller — not to the others.
class AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // Keep the chain alive regardless of this action's success/failure so a
    // failed op doesn't deadlock the lane.
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
