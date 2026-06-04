// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git_status.dart';
import 'package:nexus_projects_client/features/project_plans/plan_store.dart';
import 'package:nexus_projects_client/features/workspace/code_highlight.dart';

/// Center pane for Project Plans: a live-highlighted markdown editor for the
/// opened plan. Plans are real files under `/PLANS`, addressed by path. To edit
/// a plan conversationally, use the project Chat tab — the Coordinator can
/// read/rewrite any plan via its plan tools.
class PlanWorkspaceView extends ConsumerWidget {
  const PlanWorkspaceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider);
    final openPath = ref.watch(openPlanNotifierProvider);

    if (openPath == null) {
      return _placeholder(context);
    }

    // Re-walks when the workspace mutates (e.g. plan edited via Chat).
    final revision = ref.watch(workspaceRevisionProvider(projectId));
    final plansAsync = ref.watch(plansForProjectProvider(projectId));

    return plansAsync.when(
      data: (plans) {
        PlanNode? node;
        for (final p in plans) {
          if (p.path == openPath) {
            node = p;
            break;
          }
        }
        if (node == null || node.isFolder) {
          return _placeholder(context);
        }
        final pl = node;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pl.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _PlanEditor(
                key: ValueKey('plan-edit-${pl.path}-$revision'),
                projectId: projectId,
                path: pl.path,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 44,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'No plan open',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pick a plan from the explorer on the right, or create one with the + button.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live-highlighted markdown editor for a plan document. Keyed by path +
/// workspace revision so it reloads with fresh content when the plan changes
/// (e.g. edited via Chat). Saves write the file and bump the workspace + git
/// status revisions so the rest of the UI refreshes.
class _PlanEditor extends ConsumerStatefulWidget {
  final int projectId;
  final String path;
  const _PlanEditor({super.key, required this.projectId, required this.path});

  @override
  ConsumerState<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends ConsumerState<_PlanEditor> {
  final CodeController _editor = CodeController();
  String _loaded = '';
  bool _ready = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ensureHighlightLanguages();
    _editor.language = languageModeForPath(widget.path);
    _editor.addListener(() {
      final d = _editor.text != _loaded;
      if (d != _dirty) setState(() => _dirty = d);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final store = await ref.read(planStoreProvider(widget.projectId).future);
      final content = await store.read(widget.path);
      if (!mounted) return;
      setState(() {
        _loaded = content;
        _editor.text = content;
        _ready = true;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final store = await ref.read(planStoreProvider(widget.projectId).future);
      await store.write(widget.path, _editor.text);
      ref.read(workspaceRevisionProvider(widget.projectId).notifier).state++;
      ref.read(gitStatusRevisionProvider(widget.projectId).notifier).state++;
      if (mounted) {
        setState(() {
          _loaded = _editor.text;
          _dirty = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Plan saved.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        Expanded(
          child: Container(
            color: highlightBackground(brightness),
            child: CodeTheme(
              data: CodeThemeData(styles: highlightThemeFor(brightness)),
              child: CodeField(
                controller: _editor,
                expands: true,
                wrap: false,
                background: highlightBackground(brightness),
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
                gutterStyle: const GutterStyle(
                  showLineNumbers: true,
                  showErrors: false,
                  showFoldingHandles: false,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (_dirty)
                const Text(
                  'Unsaved changes',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                )
              else
                const Text(
                  'Saved',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: (_dirty && !_saving) ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
