// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/infrastructure/models/ui/task.dart';
import 'package:nexus_projects_client/core/providers/tasks_provider.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/projects/coordinator_chat_screen.dart';

import '../../shared/ui/nexus_ui.dart';

/// Main Project Overview page (renamed from "Project Plans" during refactor).
/// Shows project summary, agent assignment, and plan management.
class ProjectPlansView extends ConsumerWidget {
  const ProjectPlansView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentClientId = ref.watch(currentClientIdProvider);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Project Overview',
            subtitle:
                'Manage your project overview, assign an Agent persona to the Coordinator, and generate task subtrees from plans.',
          ),
          Gap.md,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => _createNewPlan(context),
                icon: const Icon(Icons.add),
                label: const Text('New Plan'),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.link),
                label: const Text('Link Plans'),
              ),
              GradientButton(
                icon: Icons.call,
                label: 'Talk to Coordinator',
                onPressed: () async {
                  final projectId = ref.read(currentProjectIdProvider);
                  String projectName = projectId.toString();
                  try {
                    final db = ref.read(nexusDatabaseProvider);
                    final projects = await db.getProjectsForClient(
                      ref.read(currentClientIdProvider),
                    );
                    final match = projects
                        .where((p) => p.project_pk == projectId)
                        .firstOrNull;
                    if (match != null) projectName = match.name;
                  } catch (_) {}
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProjectCoordinatorChatScreen(
                        projectId: projectId,
                        projectName: projectName,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          Gap.lg,

          // ==================== Agent Selector Card ====================
          _AgentSelectorCard(currentClientId: currentClientId),

          Gap.lg,

          Expanded(
            child: ListView(
              children: [
                _PlanCard(
                  title: 'Authentication Overhaul',
                  description:
                      'JWT refresh rotation, revocation, and secure storage strategy.',
                  linkedPlans: ['Security Hardening', 'Token Lifecycle'],
                  onGenerateTasks: () => _generateTaskSubtreeFromPlan(
                    context,
                    ref,
                    'Authentication Overhaul',
                  ),
                  onEdit: () =>
                      _showEditPlanDialog(context, 'Authentication Overhaul'),
                ),
                _PlanCard(
                  title: 'CI/CD Modernization',
                  description:
                      'Matrix builds, better caching, and deployment gates.',
                  linkedPlans: ['Build Performance'],
                  onGenerateTasks: () => _generateTaskSubtreeFromPlan(
                    context,
                    ref,
                    'CI/CD Modernization',
                  ),
                  onEdit: () =>
                      _showEditPlanDialog(context, 'CI/CD Modernization'),
                ),
                _PlanCard(
                  title: 'Observability & Audit',
                  description:
                      'Immutable traces, policy gates, and compliance exports.',
                  linkedPlans: [],
                  onGenerateTasks: () => _generateTaskSubtreeFromPlan(
                    context,
                    ref,
                    'Observability & Audit',
                  ),
                  onEdit: () =>
                      _showEditPlanDialog(context, 'Observability & Audit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _createNewPlan(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Plan'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Plan name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('New plan created (demo)')),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditPlanDialog(BuildContext context, String title) {
    final ctrl = TextEditingController(text: title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Plan: $title'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Plan name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Plan "$title" updated (demo)')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _generateTaskSubtreeFromPlan(
    BuildContext context,
    WidgetRef ref,
    String planName,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final root = Task(
      id: 'plan-$now',
      title: '[$planName] - Master Plan Execution',
      description: 'Generated by Mastermind from plan: $planName',
      status: 'Agent Active',
      priority: 'HIGH',
      parentId: null,
      childIds: ['plan-${now}-1', 'plan-${now}-2'],
    );
    ref.read(tasksNotifierProvider.notifier).addTask(root);
    ref
        .read(tasksNotifierProvider.notifier)
        .addTask(
          Task(
            id: 'plan-$now-1',
            title: 'Break down plan into actionable sub-tasks',
            description: '',
            status: 'Todo',
            priority: 'HIGH',
            parentId: 'plan-$now',
          ),
        );
    ref
        .read(tasksNotifierProvider.notifier)
        .addTask(
          Task(
            id: 'plan-$now-2',
            title: 'Research and validate approach',
            description: '',
            status: 'Todo',
            priority: 'MED',
            parentId: 'plan-$now',
          ),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Mastermind generated task subtree from "$planName"'),
        action: SnackBarAction(label: 'View in Tasks', onPressed: () {}),
      ),
    );
  }
}

/// Agent selector card — lets the project pick an Agent persona.
class _AgentSelectorCard extends ConsumerWidget {
  final int currentClientId;
  const _AgentSelectorCard({required this.currentClientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personasAsync = ref.watch(
      agentPersonasForClientProvider(currentClientId),
    );
    return NexusCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.smart_toy_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Assign Agent Persona',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose an Agent from the Agents/Personas list. Its models, capabilities, and modality routing will be used by this project.',
            style: TextStyle(fontSize: 12, color: context.nx.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          personasAsync.when(
            data: (personas) {
              if (personas.isEmpty)
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'No agents configured. Create one in the Agents/Personas page.',
                    style: TextStyle(fontSize: 12, color: context.nx.textMuted),
                  ),
                );
              final items = <DropdownMenuItem<int?>>[
                const DropdownMenuItem(
                  value: null,
                  child: Text('No agent assigned'),
                ),
              ];
              for (final p in personas) {
                String info = '${p.primaryModel ?? 'Default'}';
                if (p.provider_fk != null) info += ' (via provider)';
                items.add(
                  DropdownMenuItem(
                    value: p.agent_pk,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          info,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.nx.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return FutureBuilder(
                future: _getCurrentAgent(ref),
                builder: (context, snap) {
                  // Only use the saved id if it maps to exactly one item in this
                  // client's persona list; otherwise fall back to "No agent assigned".
                  // (A stale id, or one from another client, would otherwise trip
                  // DropdownButton's "exactly one item with value" assertion.)
                  final rawId = snap.data;
                  final currentId =
                      (rawId != null &&
                          personas.where((p) => p.agent_pk == rawId).length ==
                              1)
                      ? rawId
                      : null;
                  return DropdownButtonFormField<int?>(
                    initialValue: currentId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Select Agent',
                      isDense: true,
                    ),
                    items: items,
                    isExpanded: true,
                    // The menu items are two lines; render a single line in the
                    // collapsed button so it doesn't overflow the dense field.
                    selectedItemBuilder: (context) => [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No agent assigned',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      for (final p in personas)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                    ],
                    onChanged: (v) => _assignAgent(ref, v),
                  );
                },
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  Future<int?> _getCurrentAgent(WidgetRef ref) async {
    try {
      final db = ref.read(nexusDatabaseProvider);
      return await db.getProjectAgentPersonaId(
        ref.read(currentProjectIdProvider),
      );
    } catch (_) {}
    return null;
  }

  Future<void> _assignAgent(WidgetRef ref, int? personaId) async {
    try {
      final db = ref.read(nexusDatabaseProvider);
      await db.setProjectAgentPersona(
        ref.read(currentProjectIdProvider),
        personaId,
      );
    } catch (e) {
      debugPrint('Error assigning agent: $e');
    }
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String description;
  final List<String> linkedPlans;
  final VoidCallback onGenerateTasks;
  final VoidCallback onEdit;

  const _PlanCard({
    required this.title,
    required this.description,
    required this.linkedPlans,
    required this.onGenerateTasks,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: NexusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(description, style: TextStyle(color: context.nx.textMuted)),
            if (linkedPlans.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: linkedPlans
                    .map(
                      (p) =>
                          StatusChip(p, intent: ChipIntent.info, dense: true),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onGenerateTasks,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate Tasks'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit Plan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
