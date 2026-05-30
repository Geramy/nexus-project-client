// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'git/git_engine_provider.dart';

/// Per-file git state, mapped from whatever git engine we wire in (libgit2 via
/// git2dart, or a pure-Dart engine). Engine-agnostic on purpose.
enum GitFileStatus {
  clean, // tracked & unmodified (synced/committed)
  untracked, // not yet tracked
  modified, // working-tree change, not staged
  staged, // staged change (in the index)
  added, // new file, staged
  deleted, // removed
  renamed, // moved/renamed
  conflicted, // merge conflict
  ignored, // matched by .gitignore
}

/// Visual treatment for a status, VS Code-style: a one-letter badge, a tint for
/// the filename, and muted/strike flags.
class GitDecoration {
  final String badge;
  final Color color;
  final bool muted;
  final bool strike;
  final String tooltip;
  const GitDecoration(this.badge, this.color, this.tooltip, {this.muted = false, this.strike = false});
}

GitDecoration? gitDecorationFor(GitFileStatus s) {
  switch (s) {
    case GitFileStatus.clean:
      return null; // no decoration — synced
    case GitFileStatus.modified:
      return const GitDecoration('M', Color(0xFFE2A03F), 'Modified (unstaged)');
    case GitFileStatus.staged:
      return const GitDecoration('M', Color(0xFF4FA66A), 'Staged');
    case GitFileStatus.added:
      return const GitDecoration('A', Color(0xFF4FA66A), 'Added (staged)');
    case GitFileStatus.untracked:
      return const GitDecoration('U', Color(0xFF4FA66A), 'Untracked');
    case GitFileStatus.deleted:
      return const GitDecoration('D', Color(0xFFD16969), 'Deleted', strike: true);
    case GitFileStatus.renamed:
      return const GitDecoration('R', Color(0xFFE2A03F), 'Renamed');
    case GitFileStatus.conflicted:
      return const GitDecoration('!', Color(0xFFD16969), 'Merge conflict');
    case GitFileStatus.ignored:
      return const GitDecoration('', Colors.grey, 'Ignored', muted: true);
  }
}

/// Whether a status should bubble up to color a parent folder (any pending change).
bool gitStatusIsDirty(GitFileStatus s) =>
    s != GitFileStatus.clean && s != GitFileStatus.ignored;

/// A snapshot of a workspace's git state for decorating the tree.
class GitStatusSnapshot {
  /// Whether the workspace is a git repo at all.
  final bool hasRepo;

  /// Current branch (e.g. "main"), if any.
  final String? branch;

  /// Whether the working tree is clean (no pending changes).
  final bool isClean;

  /// Commits ahead / behind the upstream, if known.
  final int ahead;
  final int behind;

  /// Workspace path ("/src/main.dart") -> status. Paths absent here are clean.
  final Map<String, GitFileStatus> byPath;

  const GitStatusSnapshot({
    required this.hasRepo,
    this.branch,
    this.isClean = true,
    this.ahead = 0,
    this.behind = 0,
    this.byPath = const {},
  });

  static const GitStatusSnapshot noRepo = GitStatusSnapshot(hasRepo: false);

  GitFileStatus statusFor(String wsPath) => byPath[wsPath] ?? GitFileStatus.clean;

  /// Aggregate status for a folder: dirty if any descendant path is dirty.
  bool folderHasChanges(String folderWsPath) {
    final prefix = folderWsPath == '/' ? '/' : '$folderWsPath/';
    for (final e in byPath.entries) {
      if ((folderWsPath == '/' || e.key.startsWith(prefix)) && gitStatusIsDirty(e.value)) {
        return true;
      }
    }
    return false;
  }
}

/// Source of git status for a project's workspace. The real implementation lands
/// with the git engine (git2dart/libgit2 or pure-Dart); until then we report
/// "no repo" so the tree renders cleanly without decorations.
abstract class GitStatusSource {
  Future<GitStatusSnapshot> snapshot(int projectId);
}

/// libgit2-backed git status, sourced from the SQLite-bound git engine.
final gitStatusSourceProvider = Provider<GitStatusSource>((ref) => NxtprjGitStatusSource(ref));

/// Git status for a project's workspace (decorates the file tree). Refreshes
/// when [gitStatusRevisionProvider] is bumped (after commits/stages/etc.).
final gitStatusProvider = FutureProvider.family<GitStatusSnapshot, int>((ref, projectId) async {
  ref.watch(gitStatusRevisionProvider(projectId));
  return ref.watch(gitStatusSourceProvider).snapshot(projectId);
});

final gitStatusRevisionProvider = StateProvider.family<int, int>((ref, projectId) => 0);
