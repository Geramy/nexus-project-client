// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart' show AgentPersonasCompanion;
import 'package:nexus_projects_client/features/agents/persona_bulk_select.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Personas tab (with prefab badges, clone, publish, editor navigation).
/// Extracted from the monolithic center_agents_view during organization refactor.
class PersonasTab extends ConsumerStatefulWidget {
  const PersonasTab({super.key});

  @override
  ConsumerState<PersonasTab> createState() => _PersonasTabState();
}

class _PersonasTabState extends ConsumerState<PersonasTab> {
  @override
  Widget build(BuildContext context) {
    final currentClientId = ref.watch(currentClientIdProvider);
    final personasAsync = ref.watch(agentPersonasForClientProvider(currentClientId));
    final selectedId = ref.watch(selectedPersonaNotifierProvider)?.id;
    final selection = ref.watch(personaBulkSelectionProvider);
    final selectNotifier = ref.read(personaBulkSelectionProvider.notifier);

    return personasAsync.when(
      data: (personas) {
        final allIds = personas.map((p) => p.agent_pk).toSet();
        return Column(
          children: [
            _SelectionToolbar(
              selectMode: selection.active,
              selectedCount: selection.count,
              totalCount: personas.length,
              allSelected: selection.count == allIds.length && allIds.isNotEmpty,
              onEnter: personas.isEmpty
                  ? null
                  : () {
                      // Drop the single-persona editor so the right outer panel
                      // can host the bulk editor instead.
                      ref.read(selectedPersonaNotifierProvider.notifier).clear();
                      selectNotifier.enter();
                    },
              onCancel: selectNotifier.exit,
              onToggleAll: () => selectNotifier.toggleAll(allIds),
            ),
            const Divider(height: 1),
            Expanded(
              child: personas.isEmpty
                  ? const EmptyState(
                      icon: Icons.smart_toy_outlined,
                      title: 'No personas yet',
                      message:
                          'No personas for this client yet. Create one to start delegating work.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        for (final p in personas)
                          _PersonaCard(
                            persona: p,
                            selectMode: selection.active,
                            checked: selection.ids.contains(p.agent_pk),
                            selected: !selection.active && p.agent_pk == selectedId,
                            onToggle: () => selectNotifier.toggle(p.agent_pk),
                            onClone: () => _showClonePersonaDialog(
                                context, ref, p, currentClientId),
                            onEdit: () {
                              ref
                                  .read(selectedPersonaNotifierProvider.notifier)
                                  .select(
                                    EditingPersona(id: p.agent_pk, name: p.name),
                                  );
                            },
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

/// Header strip that toggles multi-select mode and launches the bulk editor.
class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectMode,
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onEnter,
    required this.onCancel,
    required this.onToggleAll,
  });

  final bool selectMode;
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback? onEnter;
  final VoidCallback onCancel;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: selectMode
          ? Row(
              children: [
                Text('$selectedCount selected',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: onToggleAll,
                  child: Text(allSelected ? 'Clear all' : 'Select all'),
                ),
                const Spacer(),
                Text('Edit in the right panel →',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor)),
                const SizedBox(width: AppSpacing.sm),
                TextButton(onPressed: onCancel, child: const Text('Done')),
              ],
            )
          : Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onEnter,
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text('Select'),
              ),
            ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final dynamic persona; // Drift row or UI model
  final bool selected;
  final bool selectMode;
  final bool checked;
  final VoidCallback onToggle;
  final VoidCallback onClone;
  final VoidCallback onEdit;

  const _PersonaCard({
    required this.persona,
    required this.selected,
    required this.selectMode,
    required this.checked,
    required this.onToggle,
    required this.onClone,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = selectMode ? checked : selected;
    final name = persona.name;
    // Show what the persona is actually configured to use: the Omni Collection
    // first, then the text-generation (LLM) model, falling back to the legacy
    // primaryModel. (primaryModel is set at creation and never updated by the
    // editor, so it would otherwise show a stale default like claude-3-5-sonnet.)
    final String? omni = persona.omniCollectionModel;
    final String? llm = persona.llmModel;
    final model = (omni != null && omni.isNotEmpty)
        ? omni
        : (llm != null && llm.isNotEmpty)
            ? llm
            : (persona.primaryModel ?? 'Default');
    final cost = persona.costPerMillionTokens > 0
        ? '\$${persona.costPerMillionTokens.toStringAsFixed(3)}/M'
        : 'Free';

    final isPrefab = persona.isPrefab;
    final isInstance = persona.prefab_fk != null;
    final hasOverrides = persona.overridesJson != '{}' && persona.overridesJson.isNotEmpty;

    final nx = context.nx;
    final avatarColor = isPrefab
        ? theme.colorScheme.primary
        : isInstance
            ? (hasOverrides ? nx.warning : nx.info)
            : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: NexusCard(
        padding: EdgeInsets.zero,
        selected: highlighted,
        onTap: selectMode ? onToggle : onEdit,
        child: ListTile(
          selected: highlighted,
          leading: selectMode
              ? Checkbox(value: checked, onChanged: (_) => onToggle())
              : CircleAvatar(
                  backgroundColor: avatarColor.withValues(alpha: 0.18),
                  child: Icon(Icons.smart_toy, color: avatarColor),
                ),
          title: Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (isPrefab) ...[
                const SizedBox(width: AppSpacing.sm),
                const StatusChip('PREFAB', intent: ChipIntent.accent, dense: true),
              ] else if (isInstance) ...[
                const SizedBox(width: AppSpacing.sm),
                StatusChip(
                  hasOverrides ? 'OVERRIDDEN' : 'FROM PREFAB',
                  intent: hasOverrides ? ChipIntent.warning : ChipIntent.info,
                  dense: true,
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$model • $cost'),
              if (hasOverrides)
                Text(
                  'Has local modifications',
                  style: TextStyle(fontSize: 11, color: nx.warning, fontStyle: FontStyle.italic),
                ),
            ],
          ),
          isThreeLine: hasOverrides,
          trailing: selectMode
              ? null
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPrefab)
                Tooltip(
                  message: 'This is a reusable Prefab. Changes here will affect all instances.',
                  child: Icon(Icons.link, size: 18, color: theme.colorScheme.primary),
                ),
              if (isInstance && hasOverrides)
                Tooltip(
                  message: 'This instance has local overrides (diffable from prefab)',
                  child: Icon(Icons.compare_arrows, size: 18, color: nx.warning),
                ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Clone / Instantiate in another Client',
                onPressed: onClone,
              ),
              if (!isPrefab && !isInstance)
                IconButton(
                  icon: Icon(Icons.link, size: 18, color: theme.colorScheme.primary),
                  tooltip: 'Publish as Prefab',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Publishing as Prefab will be fully wired soon')),
                    );
                  },
                ),
              const Icon(Icons.edit),
            ],
          ),
          onTap: selectMode ? onToggle : onEdit,
        ),
      ),
    );
  }
}

Future<void> _showClonePersonaDialog(
  BuildContext context,
  WidgetRef ref,
  dynamic persona,
  int currentClientId,
) async {
  final clients = await ref.read(nexusDatabaseProvider).getAllClients();
  final otherClients = clients.where((c) => c.client_pk != currentClientId).toList();

  if (otherClients.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No other clients to clone to. Create another client first.')),
    );
    return;
  }

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Clone "${persona.name}" to another Client'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: otherClients.map((client) {
            return ListTile(
              title: Text(client.name + (client.isDefault ? ' (Default)' : '')),
              onTap: () async {
                final db = ref.read(nexusDatabaseProvider);
                await db.createAgentPersona(
                  AgentPersonasCompanion.insert(
                    client_fk: client.client_pk,
                    name: '${persona.name} (cloned)',
                    description: Value(persona.description),
                    primaryModel: Value(persona.primaryModel),
                    costPerMillionTokens: Value(persona.costPerMillionTokens),
                    capabilitiesJson: Value(persona.capabilitiesJson),
                    configJson: Value(persona.configJson),
                    provider_fk: Value(persona.provider_fk),
                    omniCollectionModel: Value(persona.omniCollectionModel),
                    ttsModel: Value(persona.ttsModel),
                    sttModel: Value(persona.sttModel),
                    imageGenModel: Value(persona.imageGenModel),
                    visionModel: Value(persona.visionModel),
                    llmModel: Value(persona.llmModel),
                  ),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Cloned persona to "${client.name}"')),
                );
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ],
    ),
  );
}
