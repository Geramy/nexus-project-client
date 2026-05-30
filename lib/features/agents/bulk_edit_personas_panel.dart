// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show AgentPersonasCompanion, InferenceServer;
import 'package:nexus_projects_client/features/ai_providers/providers/ai_servers_cache_provider.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/api/types/model_info.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/services/persona_model_resolver.dart';
import 'package:nexus_projects_client/features/agents/agent_role.dart';
import 'package:nexus_projects_client/features/agents/agent_tool_permissions.dart';
import 'package:nexus_projects_client/features/agents/persona_bulk_select.dart';

/// Bulk-edit form for multiple agent personas, hosted in the MainShell right
/// outer panel while Personas select mode is active. Only fields whose "apply"
/// switch is enabled are written; every other column is left untouched on each
/// selected persona (Value.absent()). Reads the live selection from
/// [personaBulkSelectionProvider] so the count tracks the list checkboxes.
class BulkEditPersonasPanel extends ConsumerStatefulWidget {
  const BulkEditPersonasPanel({super.key, required this.clientId});

  final int clientId;

  @override
  ConsumerState<BulkEditPersonasPanel> createState() =>
      _BulkEditPersonasPanelState();
}

class _BulkEditPersonasPanelState extends ConsumerState<BulkEditPersonasPanel> {
  // Which fields to apply.
  bool _applyServer = false;
  bool _applyModels = false;
  bool _applyRole = false;
  bool _applyTools = false;

  // Values.
  int? _serverId; // provider_fk + source server for the model lists.
  String? _omniCollection;
  final Map<String, String?> _mods = {
    'tts': null,
    'stt': null,
    'imageGen': null,
    'vision': null,
    'llm': null,
  };
  AgentRole? _role;
  final Map<String, ToolPerm> _toolPerms = {};

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final t in kCoordinatorToolSpecs) {
      _toolPerms[t.name] = t.defaultPerm;
    }
  }

  bool get _modelsNeedServer => _applyModels && _serverId == null;

  bool _canApply(int selectedCount) =>
      selectedCount > 0 &&
      (_applyServer || _applyModels || _applyRole || _applyTools) &&
      !_modelsNeedServer &&
      !_busy;

  Future<void> _apply(List<int> personaIds) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final db = ref.read(nexusDatabaseProvider);
      final cache = ref.read(aiServersCacheProvider);
      final entry = _serverId != null ? cache[_serverId!] : null;

      // Resolve real per-modality model ids exactly like the single editor.
      final resolved = _applyModels
          ? resolvePersonaModels(
              omniCollectionModel: _omniCollection,
              llmModel: _mods['llm'],
              sttModel: _mods['stt'],
              ttsModel: _mods['tts'],
              visionModel: _mods['vision'],
              imageGenModel: _mods['imageGen'],
              models: entry?.models ?? const <ApiModelInfo>[],
            )
          : null;

      var updated = 0;
      for (final id in personaIds) {
        // Tool permissions merge into each persona's existing configJson.
        Value<String> configJson = const Value.absent();
        if (_applyTools) {
          final row = await db.resolveAgentPersona(id);
          configJson = Value(
            AgentToolPermissions.writeIntoConfigJson(row?.configJson, _toolPerms),
          );
        }

        updated += await (db.update(db.agentPersonas)
              ..where((p) => p.agent_pk.equals(id)))
            .write(
          AgentPersonasCompanion(
            provider_fk: _applyServer ? Value(_serverId) : const Value.absent(),
            omniCollectionModel:
                _applyModels ? Value(_safe(_omniCollection)) : const Value.absent(),
            ttsModel: _applyModels ? Value(resolved!.tts) : const Value.absent(),
            sttModel: _applyModels ? Value(resolved!.stt) : const Value.absent(),
            imageGenModel:
                _applyModels ? Value(resolved!.imageGen) : const Value.absent(),
            visionModel:
                _applyModels ? Value(resolved!.vision) : const Value.absent(),
            llmModel: _applyModels ? Value(resolved!.llm) : const Value.absent(),
            title: _applyRole ? Value(_role?.key) : const Value.absent(),
            configJson: configJson,
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      if (!mounted) return;
      ref.read(personaBulkSelectionProvider.notifier).exit();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated $updated personas.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Bulk update failed: $e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = ref.watch(personaBulkSelectionProvider);
    final selectedIds = selection.ids.toList();
    final serversAsync =
        ref.watch(inferenceServersForClientProvider(widget.clientId));
    ref.watch(aiServersCacheProvider); // live model lists

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.edit, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bulk edit ${selectedIds.length} '
                    '${selectedIds.length == 1 ? 'persona' : 'personas'}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Done',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _busy
                      ? null
                      : () =>
                          ref.read(personaBulkSelectionProvider.notifier).exit(),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: selectedIds.isEmpty
              ? const _EmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      Text(
                        'Only the sections you switch on are written to every '
                        'selected persona. Everything else is left as-is.',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                      const SizedBox(height: 8),
                      _section(
                        title: 'AI Provider (server)',
                        value: _applyServer,
                        onChanged: (v) => setState(() => _applyServer = v),
                        child: _serverDropdown(serversAsync),
                      ),
                      _section(
                        title: 'Models',
                        value: _applyModels,
                        onChanged: (v) => setState(() => _applyModels = v),
                        child: _modelsSection(serversAsync),
                      ),
                      _section(
                        title: 'Job Title / Role',
                        value: _applyRole,
                        onChanged: (v) => setState(() => _applyRole = v),
                        child: _roleDropdown(),
                      ),
                      _section(
                        title: 'Tool permissions',
                        value: _applyTools,
                        onChanged: (v) => setState(() => _applyTools = v),
                        child: _toolMatrix(),
                      ),
                    ],
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed:
                _canApply(selectedIds.length) ? () => _apply(selectedIds) : null,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Apply to selected'),
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          value: value,
          onChanged: _busy ? null : onChanged,
        ),
        if (value)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: child,
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _serverDropdown(AsyncValue<List<InferenceServer>> serversAsync) {
    return serversAsync.when(
      data: (srvs) {
        if (srvs.isEmpty) {
          return const Text('No AI Providers configured.',
              style: TextStyle(fontSize: 12, color: Colors.grey));
        }
        final valid =
            srvs.any((s) => s.server_pk == _serverId) ? _serverId : null;
        return DropdownButtonFormField<int?>(
          initialValue: valid,
          isExpanded: true,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), isDense: true, labelText: 'AI Provider'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Client / project default')),
            for (final s in srvs)
              DropdownMenuItem(
                value: s.server_pk,
                child: Text('${s.providerType} • ${s.name}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _serverId = v),
        );
      },
      loading: () => const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e'),
    );
  }

  Widget _modelsSection(AsyncValue<List<InferenceServer>> serversAsync) {
    final cache = ref.watch(aiServersCacheProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Models are listed from the server selected below — choose one even if '
          'you are not changing the persona\'s provider.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 8),
        _serverDropdown(serversAsync),
        const SizedBox(height: 8),
        if (_serverId == null)
          const Text('Select a server to pick models.',
              style: TextStyle(fontSize: 12, color: Colors.grey))
        else
          _modelPickers(cache[_serverId!]),
      ],
    );
  }

  Widget _modelPickers(ServerModelsEntry? entry) {
    final isLoading = entry == null;
    if (isLoading) {
      return const Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator()));
    }
    final omniModels = entry.omniModels;
    final individual = entry.individualModels;

    final omniItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(
          value: null, child: Text('No Omni Collection — use individual models')),
      for (final m in omniModels)
        DropdownMenuItem(value: m.id, child: Text(m.id, overflow: TextOverflow.ellipsis)),
    ];
    final curOmni = _omniCollection?.isNotEmpty == true &&
            omniModels.any((m) => m.id == _omniCollection)
        ? _omniCollection
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: curOmni,
          isExpanded: true,
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Omni Collection'),
          items: omniItems,
          onChanged: (v) => setState(() => _omniCollection = v),
        ),
        if (_omniCollection == null || _omniCollection!.isEmpty) ...[
          const SizedBox(height: 8),
          _modPicker('LLM', 'llm', individual),
          _modPicker('TTS', 'tts', individual),
          _modPicker('STT', 'stt', individual),
          _modPicker('Vision', 'vision', individual),
          _modPicker('Image Gen', 'imageGen', individual),
        ],
      ],
    );
  }

  Widget _modPicker(String label, String key, List<ApiModelInfo> models) {
    final cur =
        models.any((m) => m.id == _mods[key]) ? _mods[key] : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String?>(
        initialValue: cur,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
            border: const OutlineInputBorder(), isDense: true, labelText: label),
        items: [
          const DropdownMenuItem(value: null, child: Text('Use default')),
          for (final m in models)
            DropdownMenuItem(value: m.id, child: Text(m.id, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _mods[key] = v),
      ),
    );
  }

  Widget _roleDropdown() {
    return DropdownButtonFormField<AgentRole>(
      initialValue: _role,
      isExpanded: true,
      decoration: const InputDecoration(
          border: OutlineInputBorder(), isDense: true, labelText: 'Role'),
      items: [
        for (final r in AgentRole.values)
          DropdownMenuItem(
              value: r,
              child: Text(r.displayTitle, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _role = v),
    );
  }

  Widget _toolMatrix() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          TextButton(
              onPressed: () => _setAllPerms(ToolPerm.grant),
              child: const Text('Grant all')),
          TextButton(
              onPressed: () => _setAllPerms(ToolPerm.ask),
              child: const Text('Ask all')),
          TextButton(
              onPressed: () => _setAllPerms(ToolPerm.deny),
              child: const Text('Deny all')),
        ]),
        for (final category in kToolCategories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(category,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ...kCoordinatorToolSpecs.where((t) => t.category == category).map(
                (t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                        child: Text(t.label,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis)),
                    _permChip(t.name),
                  ]),
                ),
              ),
        ],
      ],
    );
  }

  void _setAllPerms(ToolPerm p) {
    setState(() {
      for (final t in kCoordinatorToolSpecs) {
        _toolPerms[t.name] = p;
      }
    });
  }

  Widget _permChip(String tool) {
    final cur = _toolPerms[tool] ?? ToolPerm.grant;
    final color = cur == ToolPerm.grant
        ? Colors.green
        : (cur == ToolPerm.ask ? Colors.orange : Colors.red);
    final label = cur == ToolPerm.grant
        ? 'Grant'
        : (cur == ToolPerm.ask ? 'Ask' : 'Deny');
    return PopupMenuButton<ToolPerm>(
      child: Chip(
          label: Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          backgroundColor: color.withValues(alpha: 0.1),
          visualDensity: VisualDensity.compact),
      itemBuilder: (_) => const [
        PopupMenuItem(value: ToolPerm.grant, child: Text('Grant')),
        PopupMenuItem(value: ToolPerm.ask, child: Text('Ask')),
        PopupMenuItem(value: ToolPerm.deny, child: Text('Deny')),
      ],
      onSelected: (v) => setState(() => _toolPerms[tool] = v),
    );
  }

  String? _safe(String? s) => (s != null && s.isNotEmpty) ? s : null;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Check personas in the list to bulk edit them.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}
