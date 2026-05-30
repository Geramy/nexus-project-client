// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../infrastructure/database/nexus_database.dart';
import 'summary_service.dart';

/// Project Summary tab: shows the AI-compiled, plain-language summary of all
/// `/PLANS` files (live from `Projects.projectSummaryMd`). The user regenerates
/// it on demand; the coordinator also refreshes it during idle cycles.
class SummaryTab extends ConsumerStatefulWidget {
  const SummaryTab({super.key, required this.projectId, required this.clientId});

  final int projectId;
  final int clientId;

  @override
  ConsumerState<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<SummaryTab> {
  bool _busy = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(summaryServiceProvider).generate(
            projectId: widget.projectId,
            clientId: widget.clientId,
          );
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
              const Expanded(
                child: Text('Project Summary',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
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
        if (_error != null)
          Container(
            width: double.infinity,
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.all(10),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.onErrorContainer)),
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
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
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
