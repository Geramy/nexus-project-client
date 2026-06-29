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

  /// Run [action] once the lane is free, then advance the chain.
  ///
  /// [timeout] is a SAFETY VALVE, not a normal control flow: if the action's
  /// future never completes (e.g. a libgit2/SQLite step that hangs awaiting a
  /// lock that never frees), the chain would otherwise be wedged forever and
  /// EVERY later op on this lane would block — freezing the whole orchestrator
  /// until the app restarts. When [timeout] elapses, the caller gets a
  /// [TimeoutException] AND the chain advances (via the existing onError path),
  /// so the next waiter proceeds. This is safe because a hung op here is parked
  /// on an `await` — it isn't mutating the object DB concurrently — so letting
  /// the next op run can't interleave two live writes.
  Future<T> run<T>(Future<T> Function() action, {Duration? timeout}) {
    var result = _tail.then((_) => action());
    if (timeout != null) {
      result = result.timeout(timeout);
    }
    // Keep the chain alive regardless of this action's success/failure/timeout
    // so a failed or hung op doesn't deadlock the lane.
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
