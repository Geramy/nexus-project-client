// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../git_status.dart';
import '../vhd_workspace.dart';
import '../workspace_provider.dart';
import 'nxtprj_git_engine.dart';

/// The libgit2-backed git engine for a project, bound to its `.nxtprj` virtual
/// disk. Cached per project; disposed (freeing the repo + custom backends) when
/// no longer watched.
///
/// The engine and the [VhdWorkspace] it wraps share one SQLite handle on one
/// isolate, as required by the synchronous `NativeCallable.isolateLocal`
/// backend callbacks.
final gitEngineProvider = FutureProvider.family<NxtprjGitEngine, int>((
  ref,
  projectId,
) async {
  final ws =
      await ref.watch(workspaceFsProvider(projectId).future) as VhdWorkspace;
  final engine = await NxtprjGitEngine.open(ws);
  ref.onDispose(engine.dispose);
  return engine;
});

/// [GitStatusSource] backed by [gitEngineProvider]. Resolves the engine and
/// returns its [NxtprjGitEngine.status]; any failure degrades to "no repo" so
/// the file tree still renders cleanly.
class NxtprjGitStatusSource implements GitStatusSource {
  final Ref _ref;
  NxtprjGitStatusSource(this._ref);

  @override
  Future<GitStatusSnapshot> snapshot(int projectId) async {
    try {
      final engine = await _ref.watch(gitEngineProvider(projectId).future);
      return await engine.status();
    } catch (e, st) {
      // Surface engine failures so a broken libgit2 backend doesn't masquerade
      // as "no repo" (which silently hides every per-file decoration).
      debugPrint('[git] status snapshot failed: $e\n$st');
      return GitStatusSnapshot.noRepo;
    }
  }
}
