// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/nexus_ui.dart';
import '../call_system_ai_service.dart';

/// AI assistance for the call-system builder: describe the phone system in plain
/// language to generate the flow, and synthesize prompt audio with Omni TTS.
Future<void> showCallAiAssistDialog(BuildContext context, int projectId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AiAssistDialog(projectId: projectId),
  );
}

class _AiAssistDialog extends ConsumerStatefulWidget {
  const _AiAssistDialog({required this.projectId});
  final int projectId;

  @override
  ConsumerState<_AiAssistDialog> createState() => _AiAssistDialogState();
}

class _AiAssistDialogState extends ConsumerState<_AiAssistDialog> {
  final _desc = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  CallSystemAiService get _ai =>
      ref.read(callSystemAiServiceProvider(widget.projectId));

  Future<void> _run(Future<void> Function() op, String working) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = working;
    });
    try {
      await op();
      if (mounted) setState(() => _status = 'Done.');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          const Text('AI assist'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Describe the phone system you want',
              style: theme.textTheme.titleSmall,
            ),
            Gap.xs,
            Text(
              'e.g. "A dental office: greet callers, press 1 for appointments, '
              '2 for billing, 3 to leave a voicemail. After hours, send everyone '
              'to voicemail."',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.nx.textMuted,
              ),
            ),
            Gap.md,
            TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe your call flow…',
              ),
            ),
            Gap.md,
            GradientButton(
              onPressed: _busy || _desc.text.trim().isEmpty
                  ? null
                  : () => _run(
                      () => _ai.generateFlow(_desc.text.trim()),
                      'Generating the call flow…',
                    ),
              busy: _busy,
              label: 'Generate call flow',
              icon: Icons.account_tree_outlined,
              expand: true,
            ),
            Gap.sm,
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final n = await _ai.synthesizePrompts(force: true);
                      if (mounted) {
                        setState(() => _status = 'Synthesized $n prompt(s).');
                      }
                    }, 'Synthesizing prompt audio with Omni TTS…'),
              icon: const Icon(Icons.graphic_eq, size: 18),
              label: const Text('Synthesize all prompt audio'),
            ),
            if (_status != null && _error == null) ...[
              Gap.sm,
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_status!, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              Gap.sm,
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
