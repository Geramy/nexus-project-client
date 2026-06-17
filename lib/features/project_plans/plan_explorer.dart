// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git_status.dart';
import 'package:nexus_projects_client/features/project_plans/plan_store.dart';

/// Right-panel virtual file explorer for a project's plans (folders + plan
/// files under `/PLANS` in the project workspace). Click a plan to open it in
/// the workspace; create/rename/delete here. Plans are real files, so every
/// mutation bumps the workspace + git status revisions to refresh the UI.
class PlanExplorer extends ConsumerStatefulWidget {
  const PlanExplorer({super.key});

  @override
  ConsumerState<PlanExplorer> createState() => _PlanExplorerState();
}

class _PlanExplorerState extends ConsumerState<PlanExplorer> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final projectId = ref.watch(currentProjectIdProvider);
    final plansAsync = ref.watch(plansForProjectProvider(projectId));
    final openPath = ref.watch(openPlanProvider);

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Plans',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  tooltip: 'New folder',
                  onPressed: () =>
                      _create(projectId, parentPath: null, isFolder: true),
                ),
                IconButton(
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  tooltip: 'New plan',
                  onPressed: () =>
                      _create(projectId, parentPath: null, isFolder: false),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _projectAgentBar(projectId),
          const Divider(height: 1),
          Expanded(
            child: plansAsync.when(
              data: (plans) {
                if (plans.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No plans yet.\nUse the + buttons to add a plan or folder.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  );
                }
                final roots = plans.where((p) => p.parent == plansRoot).toList()
                  ..sort(_byKind);
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final r in roots)
                      ..._buildNode(r, plans, openPath, 0, projectId),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $e', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Folders first, then alphabetical by name.
  int _byKind(PlanNode a, PlanNode b) {
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// The project's Coordinator agent — drives the model/voice the Coordinator
  /// uses in Chat mode. Reactive (reads the project's agent_persona_fk).
  Widget _projectAgentBar(int projectId) {
    final clientId = ref.watch(currentClientIdProvider);
    final personasAsync = ref.watch(agentPersonasForClientProvider(clientId));
    final projsAsync = ref.watch(projectsForClientProvider(clientId));

    return personasAsync.when(
      data: (personas) {
        int? current;
        for (final p in (projsAsync.asData?.value ?? const [])) {
          if (p.project_pk == projectId) {
            current = p.agent_persona_fk;
            break;
          }
        }
        final valid =
            current != null && personas.any((p) => p.agent_pk == current)
            ? current
            : null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.smart_toy_outlined,
                    size: 14,
                    color: Colors.purple,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Coordinator Agent',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int?>(
                initialValue: valid,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text(
                      'No agent (server default)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final p in personas)
                    DropdownMenuItem(
                      value: p.agent_pk,
                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) async {
                  await ref
                      .read(nexusDatabaseProvider)
                      .setProjectAgentPersona(projectId, v);
                  if (!mounted) return;
                  final name = v == null
                      ? 'none (server default)'
                      : personas
                            .firstWhere(
                              (p) => p.agent_pk == v,
                              orElse: () => personas.first,
                            )
                            .name;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Coordinator agent set to: $name'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              if (personas.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'No personas yet — create one in Agents.',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 4),
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  List<Widget> _buildNode(
    PlanNode node,
    List<PlanNode> all,
    String? openPath,
    int depth,
    int projectId,
  ) {
    final isOpen = node.path == openPath;
    final children = all.where((p) => p.parent == node.path).toList()
      ..sort(_byKind);
    final expanded = _expanded.contains(node.path);

    final row = InkWell(
      onTap: () {
        if (node.isFolder) {
          setState(
            () => expanded
                ? _expanded.remove(node.path)
                : _expanded.add(node.path),
          );
        } else {
          ref.read(openPlanProvider.notifier).open(node.path);
          ref.read(planModeProvider.notifier).set(PlanMode.edit);
        }
      },
      child: Container(
        color: isOpen
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        padding: EdgeInsets.only(
          left: 8.0 + depth * 14,
          top: 5,
          bottom: 5,
          right: 4,
        ),
        child: Row(
          children: [
            Icon(
              node.isFolder
                  ? (expanded ? Icons.folder_open : Icons.folder)
                  : Icons.description_outlined,
              size: 16,
              color: node.isFolder ? Colors.amber.shade700 : Colors.blueGrey,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _rowMenu(node, projectId),
          ],
        ),
      ),
    );

    return [
      row,
      if (node.isFolder && expanded)
        for (final c in children)
          ..._buildNode(c, all, openPath, depth + 1, projectId),
    ];
  }

  Widget _rowMenu(PlanNode node, int projectId) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, size: 16),
      padding: EdgeInsets.zero,
      tooltip: 'Options',
      itemBuilder: (_) => [
        if (node.isFolder)
          const PopupMenuItem(value: 'newPlan', child: Text('New plan inside')),
        if (node.isFolder)
          const PopupMenuItem(
            value: 'newFolder',
            child: Text('New folder inside'),
          ),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
      onSelected: (v) async {
        switch (v) {
          case 'newPlan':
            setState(() => _expanded.add(node.path));
            await _create(projectId, parentPath: node.path, isFolder: false);
            break;
          case 'newFolder':
            setState(() => _expanded.add(node.path));
            await _create(projectId, parentPath: node.path, isFolder: true);
            break;
          case 'rename':
            await _rename(projectId, node);
            break;
          case 'delete':
            await _delete(projectId, node);
            break;
        }
      },
    );
  }

  /// Refresh the reactive plan tree + git status after a workspace mutation.
  void _bump(int projectId) {
    ref.read(workspaceRevisionProvider(projectId).notifier).state++;
    ref.read(gitStatusRevisionProvider(projectId).notifier).state++;
  }

  Future<void> _create(
    int projectId, {
    required String? parentPath,
    required bool isFolder,
  }) async {
    final name = await _promptName(
      isFolder ? 'New folder' : 'New plan',
      isFolder ? 'Folder name' : 'Plan name',
    );
    if (name == null || name.isEmpty) return;
    final store = await ref.read(planStoreProvider(projectId).future);
    final path = await store.create(
      parent: parentPath,
      name: name,
      isFolder: isFolder,
    );
    _bump(projectId);
    if (!isFolder) {
      ref.read(openPlanProvider.notifier).open(path);
      ref.read(planModeProvider.notifier).set(PlanMode.edit);
    }
  }

  Future<void> _rename(int projectId, PlanNode node) async {
    final name = await _promptName('Rename', 'Name', initial: node.name);
    if (name == null || name.isEmpty) return;
    final store = await ref.read(planStoreProvider(projectId).future);
    final wasOpen = ref.read(openPlanProvider) == node.path;
    final newPath = await store.rename(node.path, name);
    _bump(projectId);
    if (wasOpen) ref.read(openPlanProvider.notifier).open(newPath);
  }

  Future<void> _delete(int projectId, PlanNode node) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${node.isFolder ? 'folder' : 'plan'}'),
        content: Text(
          node.isFolder
              ? 'Delete "${node.name}" and everything inside it? Tasks generated from these plans keep their history but lose the plan link.'
              : 'Delete "${node.name}"? Tasks generated from it keep their history but lose the plan link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final store = await ref.read(planStoreProvider(projectId).future);
    await store.delete(node.path);
    _bump(projectId);
    if (ref.read(openPlanProvider) == node.path) {
      ref.read(openPlanProvider.notifier).open(null);
    }
  }

  Future<String?> _promptName(String title, String label, {String? initial}) {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
