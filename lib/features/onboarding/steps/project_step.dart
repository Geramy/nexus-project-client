// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/database/nexus_database.dart'
    show ProjectsCompanion;
import '../../agents/packs/agent_pack_catalog.dart';
import '../widgets/pack_selector.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Step 4 — name the first project and pick the agent pack(s) to provision into
/// the current client. Creating the project selects it and advances the wizard.
class ProjectStep extends ConsumerStatefulWidget {
  const ProjectStep({
    super.key,
    required this.onCreated,
    this.headline = 'Create your first project',
    this.subhead =
        'Name it and choose the team of agents to set up. You can change both later.',
    this.defaultName = 'My First Project',
  });

  /// Called after the project is created and selected.
  final VoidCallback onCreated;

  /// Copy varies by context: the onboarding wizard's first project vs. the
  /// "New Project" action elsewhere in the app (which reuses this same screen).
  final String headline;
  final String subhead;
  final String defaultName;

  @override
  ConsumerState<ProjectStep> createState() => _ProjectStepState();
}

class _ProjectStepState extends ConsumerState<ProjectStep> {
  late final TextEditingController _name =
      TextEditingController(text: widget.defaultName);
  Set<String> _packs = {kDefaultAgentPackKey};
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final clientId = ref.read(currentClientIdProvider);
      final db = ref.read(nexusDatabaseProvider);
      final projectId = await db.createProject(
        ProjectsCompanion.insert(client_fk: clientId, name: name),
      );
      // Provision the chosen pack(s) into the client (dedupes against any
      // already-seeded agents).
      await db.provisionAgentPack(clientId, agentsForPackKeys(_packs));
      ref.read(currentProjectIdProvider.notifier).selectProject(projectId);
      if (mounted) widget.onCreated();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Gap.xs,
        Text(
          widget.subhead,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: context.nx.textMuted),
        ),
        Gap.lg,
        TextField(
          controller: _name,
          decoration: const InputDecoration(
              labelText: 'Project name', border: OutlineInputBorder()),
        ),
        Gap.lg,
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Agent packs', style: theme.textTheme.titleSmall),
        ),
        Gap.sm,
        PackSelector(
          selected: _packs,
          onChanged: (next) => setState(() => _packs = next),
        ),
        Gap.lg,
        GradientButton(
          onPressed: _creating ? null : _create,
          busy: _creating,
          label: 'Create project',
          icon: Icons.arrow_forward,
          expand: true,
        ),
      ],
      ),
    );
  }
}
