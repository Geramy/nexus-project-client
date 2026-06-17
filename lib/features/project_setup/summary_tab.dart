// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../infrastructure/database/nexus_database.dart';
import '../../shared/ui/nexus_ui.dart';
import 'project_setup_wizard.dart';
import 'providers/tag_providers.dart';
import 'summary_service.dart';

/// Project Summary tab: shows the AI-compiled, plain-language summary of all
/// `/PLANS` files (live from `Projects.projectSummaryMd`). The user regenerates
/// it on demand; the coordinator also refreshes it during idle cycles.
class SummaryTab extends ConsumerStatefulWidget {
  const SummaryTab({
    super.key,
    required this.projectId,
    required this.clientId,
  });

  final int projectId;
  final int clientId;

  @override
  ConsumerState<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<SummaryTab> {
  bool _busy = false;
  String? _error;

  /// Rename the project — useful when the name was set wrong at creation and
  /// there's otherwise no way to change it.
  Future<void> _rename() async {
    final db = ref.read(nexusDatabaseProvider);
    final current =
        ref.read(projectRowProvider(widget.projectId)).value?.name ?? '';
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Project name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == current) return;
    await db.setProjectName(widget.projectId, newName);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Project renamed to "$newName".')));
    }
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(summaryServiceProvider)
          .generate(projectId: widget.projectId, clientId: widget.clientId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = ref.watch(nexusDatabaseProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.summarize_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ref
                          .watch(projectRowProvider(widget.projectId))
                          .value
                          ?.name ??
                      'Project Summary',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Rename project',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: _rename,
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _busy ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_busy ? 'Generating…' : 'Generate Project Summary'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _SetupCard(projectId: widget.projectId, clientId: widget.clientId),
        if (_error != null)
          Container(
            width: double.infinity,
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.all(10),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        Expanded(
          child: StreamBuilder<Project?>(
            stream: db.watchProject(widget.projectId),
            builder: (context, snap) {
              final summary = snap.data?.projectSummaryMd;
              final updated = snap.data?.summaryUpdatedAt;
              if (summary == null || summary.trim().isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No summary yet. Click "Generate Project Summary" to compile '
                      'all /PLANS files into a plain-language overview you can '
                      'verify.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (updated != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Updated ${updated.toLocal()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  SelectableText(summary, style: theme.textTheme.bodyMedium),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Setup entry point on the Summary: shows status and opens the resumable
/// full-screen setup wizard (start / resume / review).
class _SetupCard extends ConsumerWidget {
  const _SetupCard({required this.projectId, required this.clientId});
  final int projectId;
  final int clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status =
        ref.watch(projectRowProvider(projectId)).value?.setupStatus ??
        'notStarted';
    final (label, action, icon) = switch (status) {
      'complete' => (
        'Setup complete',
        'Review & edit',
        Icons.fact_check_outlined,
      ),
      'inProgress' || 'refining' => (
        'Setup in progress',
        'Resume setup',
        Icons.play_circle_outline,
      ),
      'skipped' => ('Setup skipped', 'Finish setup', Icons.checklist_rtl),
      _ => ('Setup not started', 'Start setup', Icons.checklist_rtl),
    };
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          FilledButton.tonalIcon(
            onPressed: () =>
                showProjectSetupWizard(context, projectId, clientId),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: Text(action),
          ),
        ],
      ),
    );
  }
}
