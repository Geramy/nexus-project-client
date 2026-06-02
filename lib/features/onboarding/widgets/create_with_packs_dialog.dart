// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../agents/packs/agent_pack_catalog.dart';
import '../../../shared/ui/nexus_ui.dart';
import 'pack_selector.dart';

/// Result of [showCreateWithPacksDialog]: the entered name plus the agent packs
/// to provision.
class CreateWithPacksResult {
  final String name;
  final Set<String> packKeys;
  const CreateWithPacksResult(this.name, this.packKeys);
}

/// A name field plus the agent-pack picker, used when creating a new client or
/// project so the user sets up their agents at the same moment. Returns null if
/// cancelled. [showPacks] lets the project flow hide the picker when the client
/// already has its agents (the user can still add packs from the client flow).
Future<CreateWithPacksResult?> showCreateWithPacksDialog(
  BuildContext context, {
  required String title,
  required String nameLabel,
  String defaultName = '',
  bool showPacks = true,
}) {
  return showDialog<CreateWithPacksResult>(
    context: context,
    builder: (_) => _CreateWithPacksDialog(
      title: title,
      nameLabel: nameLabel,
      defaultName: defaultName,
      showPacks: showPacks,
    ),
  );
}

class _CreateWithPacksDialog extends StatefulWidget {
  const _CreateWithPacksDialog({
    required this.title,
    required this.nameLabel,
    required this.defaultName,
    required this.showPacks,
  });

  final String title;
  final String nameLabel;
  final String defaultName;
  final bool showPacks;

  @override
  State<_CreateWithPacksDialog> createState() => _CreateWithPacksDialogState();
}

class _CreateWithPacksDialogState extends State<_CreateWithPacksDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.defaultName);
  Set<String> _packs = {kDefaultAgentPackKey};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, CreateWithPacksResult(name, _packs));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.nameLabel,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (widget.showPacks) ...[
                Gap.lg,
                Text('Agent packs',
                    style: Theme.of(context).textTheme.titleSmall),
                Gap.xs,
                Text(
                  'Choose the team of agents to set up. You can add more later.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Gap.md,
                PackSelector(
                  selected: _packs,
                  onChanged: (next) => setState(() => _packs = next),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
