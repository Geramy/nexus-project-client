// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/database/nexus_database.dart'
    show ProjectsCompanion;
import '../../agents/packs/agent_pack_catalog.dart';
import '../../projects/types/project_type.dart';
import '../../projects/types/project_type_selector.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Max length of a project name — must match the Projects.name DB column
/// (`text().withLength(min: 1, max: 150)`) so the UI can't submit an over-long
/// name that the insert would reject.
const int _kNameMaxLength = 150;

/// Step 4 — name the first project and pick the agent pack(s) to provision into
/// the current client. Creating the project selects it and advances the wizard.
class ProjectStep extends ConsumerStatefulWidget {
  const ProjectStep({
    super.key,
    required this.onCreated,
    this.headline = 'Create your first project',
    this.subhead =
        'Name it and choose the project type. You can change both later.',
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
  late final TextEditingController _name = TextEditingController(
    text: widget.defaultName,
  );
  String _typeKey = kDefaultProjectTypeKey;
  String? _subKey;
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
      final type = projectTypeByKey(_typeKey);
      final projectId = await db.createProject(
        ProjectsCompanion.insert(
          client_fk: clientId,
          name: name,
          projectType: Value(type.key),
          subCategory: Value(_subKey),
        ),
      );
      // Provision the type's default agent pack(s) into the client (dedupes
      // against any already-seeded agents).
      await db.provisionAgentPack(
        clientId,
        agentsForPackKeys(type.defaultAgentPackKeys),
      );
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
          Text(
            widget.headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Gap.xs,
          Text(
            widget.subhead,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.nx.textMuted,
            ),
          ),
          Gap.lg,
          TextField(
            controller: _name,
            // The Projects.name column caps at 150 chars; enforce it here so the
            // insert can't blow up, and surface a "N left" countdown once the
            // user is within 10 of the limit (hidden otherwise to stay clean).
            maxLength: _kNameMaxLength,
            buildCounter:
                (
                  context, {
                  required int currentLength,
                  required int? maxLength,
                  required bool isFocused,
                }) {
                  final remaining = _kNameMaxLength - currentLength;
                  if (remaining > 10) return null;
                  return Text(
                    '$remaining left',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: remaining <= 0
                          ? context.nx.danger
                          : context.nx.textMuted,
                    ),
                  );
                },
            decoration: const InputDecoration(
              labelText: 'Project name',
              border: OutlineInputBorder(),
            ),
          ),
          Gap.lg,
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Project type', style: theme.textTheme.titleSmall),
          ),
          Gap.sm,
          ProjectTypeSelector(
            selectedTypeKey: _typeKey,
            selectedSubKey: _subKey,
            onTypeChanged: (k) => setState(() => _typeKey = k),
            onSubChanged: (k) => setState(() => _subKey = k),
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
