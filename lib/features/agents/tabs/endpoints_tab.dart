// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:convert';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show InferenceServersCompanion;
import 'package:nexus_projects_client/features/agents/dialogs/server_config_dialog.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_model;
import 'package:nexus_projects_client/infrastructure/inference/routed_server.dart'
    show isRoutedProviderType;

/// Endpoints (Inference Servers) tab with add/clone/edit flows.
/// Extracted from the monolithic center_agents_view during organization refactor.
class EndpointsTab extends ConsumerWidget {
  const EndpointsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentClientId = ref.watch(currentClientIdProvider);
    final serversAsync = ref.watch(
      inferenceServersForClientProvider(currentClientId),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Inference Servers',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(width: 8),
              Text(
                '(Client: $currentClientId)',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () =>
                    _showAddServerDialog(context, ref, currentClientId),
                icon: const Icon(Icons.add),
                label: const Text('Add Server'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: serversAsync.when(
              data: (servers) {
                if (servers.isEmpty) {
                  return const Center(
                    child: Text(
                      'No inference servers configured for this client yet.',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: servers.length,
                  itemBuilder: (context, index) {
                    final s = servers[index];
                    final ui = _driftServerToUiModel(s);
                    final isRouter = isRoutedProviderType(s.providerType);
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isRouter
                              ? Icons.cloud_done_outlined
                              : Icons.dns_outlined,
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(s.name)),
                            if (isRouter) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Subscription',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          isRouter
                              ? 'Managed by your Nexus account — used by default while signed in'
                              : s.baseUrl,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isRouter)
                              const Tooltip(
                                message:
                                    'Provided by your subscription — cannot be removed while signed in',
                                child: Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'Clone to another Client',
                                onPressed: () => _showCloneServerDialog(
                                  context,
                                  ref,
                                  s,
                                  currentClientId,
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: isRouter
                                  ? 'Pick model'
                                  : 'Configure / Edit',
                              onPressed: () => _editServerViaDialog(
                                context,
                                ref,
                                ui,
                                currentClientId,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _editServerViaDialog(
                          context,
                          ref,
                          ui,
                          currentClientId,
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddServerDialog(
    BuildContext context,
    WidgetRef ref,
    int clientId,
  ) async {
    // Fetch existing servers for this client so we can generate a unique suggested name.
    final db = ref.read(nexusDatabaseProvider);
    final existingServers = await db.getInferenceServersForClient(clientId);

    // Helper: produce a sensible default in the required `provider-xxxx` form.
    // Scans existing names for the highest numeric suffix for the chosen type
    // so suggestions increment nicely (provider-lemonade-1, provider-grok-2, etc.).
    String suggestName(String type) {
      final t = type.toLowerCase().trim().isEmpty
          ? 'custom'
          : type.toLowerCase().trim();
      final prefix = 'provider-$t-';
      int maxN = 0;
      for (final s in existingServers) {
        final n = s.name as String? ?? '';
        if (n.startsWith(prefix)) {
          final rest = n.substring(prefix.length);
          final num = int.tryParse(rest);
          if (num != null && num > maxN) maxN = num;
        }
      }
      return '$prefix${maxN + 1}';
    }

    String selectedType = 'lemonade';
    final nameCtrl = TextEditingController(text: suggestName(selectedType));
    final urlCtrl = TextEditingController(text: 'http://localhost:13305');
    final apiKeyCtrl = TextEditingController(text: '');
    int concurrency = 4;
    int maxAgents = 8;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Inference Server'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Server Name'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Provider Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'lemonade',
                      child: Text('Lemonade'),
                    ),
                    DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                    DropdownMenuItem(value: 'grok', child: Text('Grok')),
                    DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        selectedType = v;
                        nameCtrl.text = suggestName(
                          v,
                        ); // live-update suggestion based on chosen type
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                TextField(
                  controller: apiKeyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Key (optional)',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                Text('Max Concurrency: $concurrency'),
                Slider(
                  value: concurrency.toDouble(),
                  min: 1,
                  max: 32,
                  divisions: 31,
                  onChanged: (v) => setState(() => concurrency = v.round()),
                ),
                Text('Max Agents: $maxAgents'),
                Slider(
                  value: maxAgents.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  onChanged: (v) => setState(() => maxAgents = v.round()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final db = ref.read(nexusDatabaseProvider);
                final name = nameCtrl.text.trim();
                final baseUrl = urlCtrl.text.trim();
                final apiKey = apiKeyCtrl.text.trim();

                final newPk = await db.createInferenceServer(
                  InferenceServersCompanion.insert(
                    client_fk: clientId,
                    name: name,
                    baseUrl: baseUrl,
                    apiKey: Value(apiKey),
                    maxConcurrency: Value(concurrency),
                    maxAgents: Value(maxAgents),
                    providerType: Value(selectedType),
                  ),
                );
                Navigator.pop(ctx);

                // Immediately open the full config dialog (exactly like Edit) so the user can
                // Refresh models, pick the active one, and Save — following lemonade_mobile flow.
                // This ensures availableModels get populated right after Add.
                final newUi = ui_model.InferenceServer(
                  id: newPk.toString(),
                  name: name,
                  baseUrl: baseUrl,
                  apiKey: apiKey,
                  providerType: selectedType,
                  maxConcurrency: concurrency,
                  maxAgents: maxAgents,
                );
                await _editServerViaDialog(context, ref, newUi, clientId);
              },
              child: const Text('Add Server'),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the rich ServerConfigDialog (with live controllers, Refresh models button,
  /// model picker) and persists + invalidates on Save. Used for both Edit and the
  /// post-Add configuration step. Mirrors the "configure after add" pattern in lemonade_mobile.
  Future<void> _editServerViaDialog(
    BuildContext context,
    WidgetRef ref,
    ui_model.InferenceServer ui,
    int clientId,
  ) async {
    final updated = await showDialog<ui_model.InferenceServer>(
      context: context,
      builder: (_) => ServerConfigDialog(server: ui),
    );
    if (updated != null) {
      await _updateServerInDb(ref, updated);
      ref.invalidate(inferenceServersForClientProvider(clientId));
    }
  }

  Future<void> _updateServerInDb(
    WidgetRef ref,
    ui_model.InferenceServer updated,
  ) async {
    final db = ref.read(nexusDatabaseProvider);

    final availableModelsJson = jsonEncode(updated.availableModels);
    final capabilitiesJson = jsonEncode(updated.capabilities);

    await (db.update(
      db.inferenceServers,
    )..where((s) => s.server_pk.equals(int.parse(updated.id)))).write(
      InferenceServersCompanion(
        baseUrl: Value(updated.baseUrl),
        apiKey: Value(updated.apiKey),
        selectedModel: Value(updated.selectedModel),
        availableModelsJson: Value(availableModelsJson),
        capabilitiesJson: Value(capabilitiesJson),
      ),
    );
  }

  Future<void> _showCloneServerDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic server,
    int currentClientId,
  ) async {
    final clients = await ref.read(nexusDatabaseProvider).getAllClients();
    final otherClients = clients
        .where((c) => c.client_pk != currentClientId)
        .toList();

    if (otherClients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No other clients to clone to. Create another client first.',
          ),
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clone "${server.name}" to another Client'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: otherClients.map((client) {
              return ListTile(
                title: Text(
                  client.name + (client.isDefault ? ' (Default)' : ''),
                ),
                onTap: () async {
                  final db = ref.read(nexusDatabaseProvider);

                  await db.createInferenceServer(
                    InferenceServersCompanion.insert(
                      client_fk: client.client_pk,
                      name: '${server.name} (from ${currentClientId})',
                      baseUrl: server.baseUrl,
                      apiKey: Value(server.apiKey),
                      providerType: Value(server.providerType),
                      maxConcurrency: Value(server.maxConcurrency),
                      maxAgents: Value(server.maxAgents),
                      isEnabled: Value(server.isEnabled),
                      selectedModel: Value(server.selectedModel),
                    ),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cloned server to "${client.name}"'),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

ui_model.InferenceServer _driftServerToUiModel(dynamic drift) {
  List<String> availableModels = [];
  try {
    final raw = drift.availableModelsJson as String? ?? '[]';
    availableModels = (jsonDecode(raw) as List).cast<String>();
  } catch (_) {}

  Map<String, dynamic> extraConfig = {};
  try {
    final raw = drift.extraConfigJson as String? ?? '{}';
    extraConfig = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {}

  Map<String, dynamic> capabilities = {};
  try {
    final raw = drift.capabilitiesJson as String? ?? '{}';
    capabilities = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {}

  return ui_model.InferenceServer(
    id: drift.server_pk.toString(),
    name: drift.name as String,
    baseUrl: drift.baseUrl as String,
    apiKey: drift.apiKey as String? ?? '',
    providerType: drift.providerType as String? ?? 'custom',
    maxConcurrency: drift.maxConcurrency as int? ?? 4,
    maxAgents: drift.maxAgents as int? ?? 8,
    isEnabled: drift.isEnabled as bool? ?? true,
    selectedModel: drift.selectedModel as String?,
    availableModels: availableModels,
    extraConfig: extraConfig,
    capabilities: capabilities,
  );
}
