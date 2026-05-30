// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'workspace.dart';
import 'vhd_workspace.dart';

/// Host path of a project's virtual disk file — one `.nxtprj` (SQLite) file per
/// project, holding its whole filesystem and (next) its git repository.
Future<String> projectDiskPath(int projectId) async {
  final base = (await getApplicationSupportDirectory()).path;
  return p.join(base, 'workspaces', 'project_$projectId.nxtprj');
}

/// The project's workspace: a single-file SQLite "virtual disk", accessed
/// purely through the [Workspace] API (no mounting). Cached per project; the
/// same file is later bound to the git2dart custom backend.
final workspaceFsProvider = FutureProvider.family<Workspace, int>((ref, projectId) async {
  final path = await projectDiskPath(projectId);
  // Ensure the parent dir exists before SQLite opens the file.
  await Directory(p.dirname(path)).create(recursive: true);
  final ws = await VhdWorkspace.open(path);
  ref.onDispose(() => ws.dispose());
  return ws;
});

/// Bumped to force the browser to re-list after a mutation (create/delete/move).
final workspaceRevisionProvider = StateProvider.family<int, int>((ref, projectId) => 0);

/// The currently-open file in the right-panel editor. Shared between the
/// center tree and the right-panel editor so a click in the tree opens the
/// file on the right.
final selectedWorkspaceFileProvider = StateProvider.family<String?, int>((ref, projectId) => null);
