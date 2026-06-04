// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/projects/orchestration/orchestrator_prompts.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Per-project editor for the orchestrator's prompt templates: the framing and
/// kickoff text wrapped around each role's default system prompt at the
/// implement / verify / merge stages. Edits are stored on the current project;
/// unchanged fields fall back to the built-in defaults.
class PromptsTab extends ConsumerStatefulWidget {
  const PromptsTab({super.key});

  @override
  ConsumerState<PromptsTab> createState() => _PromptsTabState();
}

class _PromptsTabState extends ConsumerState<PromptsTab> {
  final Map<OrchestratorPromptField, TextEditingController> _ctrls = {};
  int? _loadedProjectId;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    for (final f in OrchestratorPromptField.values) {
      _ctrls[f] = TextEditingController()..addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _load(int projectId) async {
    _loadedProjectId = projectId;
    final db = ref.read(nexusDatabaseProvider);
    final project = await db.getProjectById(projectId);
    final prompts = OrchestratorPrompts.fromJson(
      project?.orchestratorPromptsJson,
    );
    if (!mounted) return;
    for (final f in OrchestratorPromptField.values) {
      _ctrls[f]!.text = prompts.raw(f);
    }
    setState(() {
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final projectId = _loadedProjectId;
    if (projectId == null) return;
    final overrides = {
      for (final f in OrchestratorPromptField.values) f: _ctrls[f]!.text,
    };
    final json = OrchestratorPrompts.toJson(overrides);
    await ref
        .read(nexusDatabaseProvider)
        .setProjectOrchestratorPrompts(projectId, json);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Orchestrator prompts saved for this project.'),
      ),
    );
  }

  Future<void> _resetAll() async {
    final projectId = _loadedProjectId;
    if (projectId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all prompts'),
        content: const Text(
          'Reset every orchestrator prompt for this project back to the built-in defaults?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(nexusDatabaseProvider)
        .setProjectOrchestratorPrompts(projectId, null);
    for (final f in OrchestratorPromptField.values) {
      _ctrls[f]!.text = f.defaultValue;
    }
    if (!mounted) return;
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final projectId = ref.watch(currentProjectIdProvider);
    // (Re)load when the selected project changes.
    if (projectId != _loadedProjectId) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(projectId));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final stages = <String>[];
    for (final f in OrchestratorPromptField.values) {
      if (!stages.contains(f.stage)) stages.add(f.stage);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'These wrap the role\'s system prompt at each pipeline stage. Placeholders: '
                  '{taskId} {title} {branch} {description} {acceptanceCriteria} {verification}',
                  style: TextStyle(fontSize: 12, color: context.nx.textMuted),
                ),
              ),
              TextButton.icon(
                onPressed: _resetAll,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Reset all'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _dirty ? _save : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              for (final stage in stages) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.md,
                    bottom: AppSpacing.xs,
                  ),
                  child: SectionHeader(title: stage, dense: true),
                ),
                for (final f in OrchestratorPromptField.values.where(
                  (f) => f.stage == stage,
                ))
                  _field(f),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(OrchestratorPromptField f) {
    final isDefault = _ctrls[f]!.text.trim() == f.defaultValue.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isDefault)
                TextButton(
                  onPressed: () => setState(() {
                    _ctrls[f]!.text = f.defaultValue;
                    _dirty = true;
                  }),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _ctrls[f],
            maxLines: f.isMultiline ? 10 : 2,
            minLines: f.isMultiline ? 4 : 1,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}
