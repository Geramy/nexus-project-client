// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show AgentPersonasCompanion;

import 'tabs/personas_tab.dart';
import 'tabs/cost_usage_tab.dart';
import 'tabs/prompts_tab.dart';

import '../../shared/ui/nexus_ui.dart';

/// Agents Management Hub - thin coordinator after organization refactor (2026-05).
/// All tabs and the major server dialog now live in dedicated subfolders/files.
/// Class renamed from CenterAgentsView to AgentsHubView for clarity.
class AgentsHubView extends ConsumerWidget {
  const AgentsHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: SectionHeader(
              title: 'Agents / Personas',
              trailing: GradientButton(
                onPressed: () => _createNewPersona(context, ref),
                icon: Icons.add,
                label: 'New Persona',
              ),
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Personas'),
              Tab(text: 'Prompts'),
              Tab(text: 'Cost & Usage'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const PersonasTab(),
                const PromptsTab(),
                const CostUsageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewPersona(BuildContext context, WidgetRef ref) async {
    final currentClientId = ref.read(currentClientIdProvider);
    final nameCtrl = TextEditingController(text: 'New Persona');

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Agent Persona'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Persona Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final db = ref.read(nexusDatabaseProvider);
      await db.createAgentPersona(
        AgentPersonasCompanion.insert(
          client_fk: currentClientId,
          name: name,
          primaryModel: const Value('claude-3-5-sonnet'),
          costPerMillionTokens: const Value(0.003),
          // New personas start without a pinned AI Provider (user can assign via editor).
          // The column is nullable; omitting it (or using Value.absent()) yields NULL.
        ),
      );
    }
  }
}
