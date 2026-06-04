// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/infrastructure/workspace/workspace.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';

/// Plans live as real files inside the project's `.nxtprj` workspace, under a
/// top-level `/PLANS` folder, so they are versioned by the same git engine as
/// code. A plan document is any file under `/PLANS`; a folder is a directory.
/// A plan's identity is its full workspace path (e.g. `/PLANS/Roadmap.md`).
const String plansRoot = '/PLANS';

/// One entry in the plan tree (a plan document or a folder).
class PlanNode {
  /// Full workspace path, e.g. `/PLANS/Sprint 1/Tasks.md`.
  final String path;

  /// Basename shown in the explorer.
  final String name;

  /// Parent directory's workspace path (`/PLANS` for top-level plans).
  final String parent;
  final bool isFolder;
  const PlanNode({
    required this.path,
    required this.name,
    required this.parent,
    required this.isFolder,
  });
}

/// Path-addressed plan CRUD backed by the project [Workspace]. Files are the
/// source of truth; there is no plan database table.
class PlanStore {
  final Workspace _ws;
  PlanStore(this._ws);

  Future<void> ensureRoot() async {
    if (!await _ws.exists(plansRoot)) await _ws.createDirectory(plansRoot);
  }

  /// All plan documents and folders under `/PLANS` (excludes the root itself).
  Future<List<PlanNode>> list() async {
    await ensureRoot();
    final entries = await _ws.walk(from: plansRoot);
    return [
      for (final e in entries)
        PlanNode(
          path: e.path,
          name: e.name,
          parent: e.parent,
          isFolder: e.isDirectory,
        ),
    ];
  }

  Future<bool> isFolder(String path) async =>
      (await _ws.stat(path)).isDirectory;
  Future<String> read(String path) => _ws.readString(path);
  Future<void> write(String path, String content) async =>
      _ws.writeString(path, content);

  /// Creates a plan document or folder under [parent] (defaults to `/PLANS`).
  /// Returns the new node's workspace path.
  Future<String> create({
    String? parent,
    required String name,
    required bool isFolder,
    String content = '',
  }) async {
    await ensureRoot();
    final target = _join(parent ?? plansRoot, name);
    if (isFolder) {
      await _ws.createDirectory(target);
    } else {
      await _ws.writeString(target, content);
    }
    return target;
  }

  /// Renames a plan/folder in place. Returns the new path.
  Future<String> rename(String path, String newName) async {
    final parent = _parentOf(path);
    final target = _join(parent, newName);
    await _ws.move(path, target);
    return target;
  }

  Future<void> delete(String path) => _ws.delete(path, recursive: true);

  static String _join(String parent, String name) {
    final clean = name.trim().replaceAll('/', '-');
    final base = parent.endsWith('/')
        ? parent.substring(0, parent.length - 1)
        : parent;
    return '$base/$clean';
  }

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? plansRoot : path.substring(0, i);
  }
}

/// A [PlanStore] bound to a project's workspace.
final planStoreProvider = FutureProvider.family<PlanStore, int>((
  ref,
  projectId,
) async {
  final ws = await ref.watch(workspaceFsProvider(projectId).future);
  return PlanStore(ws);
});

/// Reactive plan tree for a project. Re-walks when the workspace mutates.
final plansForProjectProvider = FutureProvider.family<List<PlanNode>, int>((
  ref,
  projectId,
) async {
  ref.watch(workspaceRevisionProvider(projectId));
  final store = await ref.watch(planStoreProvider(projectId).future);
  return store.list();
});
