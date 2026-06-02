// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/nexus_ui.dart';
import '../export/call_system_exporter.dart';
import '../export/export_registry.dart';
import '../model/call_system_project.dart';

/// Lets the user pick an export target and preview/copy the produced artifact.
/// "Deploy to Nexus" (managed full-AI runtime) is surfaced as the first option.
Future<void> showCallExportDialog(
    BuildContext context, CallSystemProject project) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(project: project),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.project});
  final CallSystemProject project;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  CallSystemExporter _selected = kCallSystemExporters.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artifacts = _selected.export(widget.project);
    final notes = _selected.notes(widget.project);
    final combined = artifacts.entries
        .map((e) => '/* ===== ${e.key} ===== */\n${e.value}')
        .join('\n\n');

    return AlertDialog(
      title: const Text('Export call system'),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The managed option.
            NexusCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.cloud_done_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Deploy to Nexus (managed)',
                            style: theme.textTheme.titleSmall),
                        Text(
                          'Provision a number and run this flow + AI voicebot on our runtime. (Coming with the managed runtime.)',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: context.nx.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Gap.md,
            Text('Or export to a provider', style: theme.textTheme.titleSmall),
            Gap.sm,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final e in kCallSystemExporters)
                  ChoiceChip(
                    label: Text(e.displayName),
                    selected: identical(e, _selected),
                    onSelected: (_) => setState(() => _selected = e),
                  ),
              ],
            ),
            Gap.md,
            if (notes.isNotEmpty) ...[
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(n, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
              Gap.sm,
            ],
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.smAll,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    combined,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: combined));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${_selected.displayName} artifact copied.')),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}
