// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/worker_capture_provider.dart';
import '../../../infrastructure/training/ai_export.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Account → Export Tracking: one button per AI-driven flow (Setup, Stories).
/// Each writes a JSON of EVERY project's conversation for that AI — tool calls,
/// user messages, AI responses, the AI's thoughts, and any star ratings — to the
/// Downloads folder, and offers a copy-to-clipboard.
class ExportTrackingCard extends ConsumerStatefulWidget {
  const ExportTrackingCard({super.key});

  @override
  ConsumerState<ExportTrackingCard> createState() => _ExportTrackingCardState();
}

class _ExportTrackingCardState extends ConsumerState<ExportTrackingCard> {
  String? _busyKind;
  bool _busyWorker = false;

  Future<void> _exportWorker(int projectId) async {
    setState(() => _busyWorker = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await exportWorkerToolData(
        db: ref.read(nexusDatabaseProvider),
        projectId: projectId,
        now: DateTime.now(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Worker tool calls exported'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Project #$projectId · ${result.taskCount} task(s) · '
                '${result.toolCallCount} tool call(s).',
              ),
              const SizedBox(height: 10),
              const Text('Saved to:'),
              const SizedBox(height: 4),
              SelectableText(
                result.filePath,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_all, size: 16),
              label: const Text('Copy JSON'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result.json));
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('JSON copied to clipboard.')),
                );
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyWorker = false);
    }
  }

  Future<void> _export(String aiKind, String label) async {
    setState(() => _busyKind = aiKind);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final db = ref.read(nexusDatabaseProvider);
      final clientId = ref.read(currentClientIdProvider);
      final result = await exportAiTrainingData(
        db: db,
        clientId: clientId,
        aiKind: aiKind,
        now: DateTime.now(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$label exported'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.projectCount} project(s) · '
                '${result.conversationCount} conversation(s) · '
                '${result.ratingCount} rating(s).',
              ),
              const SizedBox(height: 10),
              const Text('Saved to:'),
              const SizedBox(height: 4),
              SelectableText(
                result.filePath,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_all, size: 16),
              label: const Text('Copy JSON'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result.json));
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('JSON copied to clipboard.')),
                );
              },
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyKind = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget button(String aiKind, String label, IconData icon) {
      final busy = _busyKind == aiKind;
      return OutlinedButton.icon(
        onPressed: _busyKind != null ? null : () => _export(aiKind, label),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 18),
        label: Text('Export $label'),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: NexusCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Export Tracking', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                'Export everything an AI did — tool calls, messages, responses, '
                'its thoughts, and your star ratings — as JSON, across all '
                'projects (separated by project). Saved to Downloads.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  button('setup', 'Setup AI', Icons.checklist_rtl),
                  button('stories', 'Stories AI', Icons.account_tree_outlined),
                ],
              ),
              // Worker (generalist) tool calls — PER PROJECT only (it's a huge
              // amount of data across all projects). Uses the current project.
              Builder(
                builder: (context) {
                  final projectId = ref.watch(currentProjectIdProvider);
                  if (projectId <= 0) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      Divider(color: context.nx.hairline),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Generalist tool calls (current project #$projectId)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Every tool the orchestrated workers called on this '
                        'project — name, arguments, and result — per task. '
                        'Project-scoped on purpose (it gets large).',
                        style: theme.textTheme.bodySmall,
                      ),
                      // Opt-in capture: only records while ON, so it never
                      // accumulates that volume when you're not debugging.
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: ref.watch(workerCaptureProvider),
                        onChanged: (v) =>
                            ref.read(workerCaptureProvider.notifier).set(v),
                        title: const Text(
                          'Capture worker tool calls',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          ref.watch(workerCaptureProvider)
                              ? 'Recording — run the workers, then export.'
                              : 'Off — turn on, run the workers, then export.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _busyWorker
                            ? null
                            : () => _exportWorker(projectId),
                        icon: _busyWorker
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.build_circle_outlined, size: 18),
                        label: const Text('Export worker tool calls'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
