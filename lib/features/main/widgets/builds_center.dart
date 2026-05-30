// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/builds/ci_run_tree.dart';
import 'package:nexus_projects_client/infrastructure/build/build_service_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart' show CiRun;
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';

/// Builds & CI center: a client-scoped, live view of every CI run (Docker
/// builds and local workflow runs) with the full run → job → step drill-down,
/// plus triggers to start a new build/run against the current project.
class BuildsCenter extends ConsumerWidget {
  const BuildsCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    final currentClientId = ref.watch(currentClientIdProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              PopupMenuButton<_NewRunKind>(
                onSelected: (kind) => _startRun(context, ref, kind),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _NewRunKind.dockerBuild,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.build, size: 18),
                      title: Text('Docker build'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _NewRunKind.workflow,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.account_tree, size: 18),
                      title: Text('Workflow run'),
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: Theme.of(context).colorScheme.onPrimary),
                      const SizedBox(width: 6),
                      Text('New run',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<CiRun>>(
              stream: db.watchCiRunsForClient(currentClientId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final runs = snapshot.data ?? const <CiRun>[];
                if (runs.isEmpty) {
                  return const CiRunsEmptyState(
                    icon: Icons.construction,
                    message: 'No builds or CI runs yet. Use "New run" to start one.',
                  );
                }
                return ListView.builder(
                  itemCount: runs.length,
                  itemBuilder: (context, i) => CiRunCard(db: db, run: runs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRun(BuildContext context, WidgetRef ref, _NewRunKind kind) async {
    final projectPk = ref.read(currentProjectIdProvider);
    final clientPk = ref.read(currentClientIdProvider);
    final db = ref.read(nexusDatabaseProvider);
    final project = await db.getProjectById(projectPk);
    if (!context.mounted) return;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a project first — its workspace provides the build context.')),
      );
      return;
    }

    final inputs = await showDialog<_RunInputs>(
      context: context,
      builder: (_) => _NewRunDialog(kind: kind, projectName: project.name),
    );
    if (inputs == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final ws = await ref.read(workspaceFsProvider(projectPk).future);
      final service = ref.read(buildServiceProvider);
      switch (kind) {
        case _NewRunKind.dockerBuild:
          await service.startDockerBuild(
            clientPk: clientPk,
            projectPk: projectPk,
            ws: ws,
            dockerfilePath: inputs.path,
            imageTag: inputs.tag!,
            triggeredBy: 'builds-center',
          );
        case _NewRunKind.workflow:
          await service.startWorkflowRun(
            clientPk: clientPk,
            projectPk: projectPk,
            ws: ws,
            workflowPath: inputs.path,
            triggeredBy: 'builds-center',
          );
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Run started — follow its progress in the list below.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to start run: $e')));
    }
  }
}

enum _NewRunKind { dockerBuild, workflow }

class _RunInputs {
  final String path;
  final String? tag;
  const _RunInputs(this.path, [this.tag]);
}

class _NewRunDialog extends StatefulWidget {
  final _NewRunKind kind;
  final String projectName;
  const _NewRunDialog({required this.kind, required this.projectName});

  @override
  State<_NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends State<_NewRunDialog> {
  late final TextEditingController _pathCtrl;
  late final TextEditingController _tagCtrl;

  bool get _isDocker => widget.kind == _NewRunKind.dockerBuild;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(text: _isDocker ? 'Dockerfile' : '.github/workflows/ci.yml');
    _tagCtrl = TextEditingController(
      text: '${widget.projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '-')}:latest',
    );
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isDocker ? 'New Docker build' : 'New workflow run'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pathCtrl,
            decoration: InputDecoration(
              labelText: _isDocker ? 'Dockerfile path (in workspace)' : 'Workflow YAML path (in workspace)',
            ),
          ),
          if (_isDocker) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _tagCtrl,
              decoration: const InputDecoration(labelText: 'Image tag'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final path = _pathCtrl.text.trim();
            if (path.isEmpty) return;
            if (_isDocker) {
              final tag = _tagCtrl.text.trim();
              if (tag.isEmpty) return;
              Navigator.pop(context, _RunInputs(path, tag));
            } else {
              Navigator.pop(context, _RunInputs(path));
            }
          },
          child: const Text('Start'),
        ),
      ],
    );
  }
}
