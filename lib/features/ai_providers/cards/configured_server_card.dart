// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/models/server_config.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show InferenceServersCompanion;
import 'package:nexus_projects_client/infrastructure/lemonade/services/secure_key_store.dart';
import 'package:nexus_projects_client/features/agents/dialogs/server_config_dialog.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart'
    as ui_model;
import 'package:nexus_projects_client/infrastructure/lemonade/providers/lemonade_servers_provider.dart';
import 'package:nexus_projects_client/features/ai_providers/providers/ai_servers_cache_provider.dart';

/// Card widget for a configured Lemonade server with edit/remove actions.
class ConfiguredServerCard extends ConsumerWidget {
  final ServerConfig server;
  final bool isSelected;

  const ConfiguredServerCard({
    super.key,
    required this.server,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? Colors.deepPurple.withValues(alpha: 0.06) : null,
      child: ListTile(
        leading: Icon(
          Icons.dns_outlined,
          color: isSelected ? Colors.deepPurple : null,
        ),
        title: Text(server.name),
        subtitle: Text(server.baseUrl),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isSelected)
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Select',
                onPressed: () => ref
                    .read(selectedLemonadeServerProvider.notifier)
                    .selectServer(server),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Configure',
              onPressed: () => _editServer(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () => _removeServer(context, ref),
            ),
          ],
        ),
        onTap: () => ref
            .read(selectedLemonadeServerProvider.notifier)
            .selectServer(server),
      ),
    );
  }

  Future<void> _editServer(BuildContext context, WidgetRef ref) async {
    final db = ref.read(nexusDatabaseProvider);
    final currentClientId = ref.read(currentClientIdProvider);
    final rows = await db.getInferenceServersForClient(currentClientId);

    final row = rows.firstWhere(
      (r) => r.name == server.name,
      orElse: () => throw Exception('Server not found in database'),
    );

    List<String> availableModels = [];
    try {
      final raw = row.availableModelsJson as String? ?? '[]';
      availableModels = (jsonDecode(raw) as List).cast<String>();
    } catch (_) {}

    Map<String, dynamic> capabilities = {};
    try {
      final raw = row.capabilitiesJson as String? ?? '{}';
      capabilities = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}

    final uiServer = ui_model.InferenceServer(
      id: row.server_pk.toString(),
      name: row.name,
      baseUrl: row.baseUrl,
      // The DB row is the source of truth for the key (it's what the coordinator
      // client actually uses). Fall back to SecureKeyStore only if the DB is
      // empty, for backward compatibility with keys saved before this change.
      apiKey: row.apiKey.isNotEmpty
          ? row.apiKey
          : (await SecureKeyStore.readApiKey(row.name) ?? ''),
      providerType: row.providerType,
      maxConcurrency: row.maxConcurrency,
      maxAgents: row.maxAgents,
      isEnabled: row.isEnabled,
      selectedModel: row.selectedModel,
      availableModels: availableModels,
      capabilities: capabilities,
    );

    final updated = await showDialog<ui_model.InferenceServer>(
      context: context,
      builder: (_) => ServerConfigDialog(server: uiServer),
    );

    if (updated != null) {
      final availableModelsJson = jsonEncode(updated.availableModels);
      final capabilitiesJson = jsonEncode(updated.capabilities);

      await (db.update(
        db.inferenceServers,
      )..where((s) => s.server_pk.equals(int.parse(updated.id)))).write(
        InferenceServersCompanion(
          baseUrl: Value(updated.baseUrl),
          // Persist the edited API key (was hardcoded to '' here, which wiped
          // the user's key on every save and broke auth).
          apiKey: Value(updated.apiKey),
          selectedModel: Value(updated.selectedModel),
          availableModelsJson: Value(availableModelsJson),
          capabilitiesJson: Value(capabilitiesJson),
        ),
      );

      ref.invalidate(lemonadeServersProvider);
      // Refresh the centralized cache so all consumers see updated models
      ref.read(aiServersCacheProvider.notifier).refresh();
    }
  }

  Future<void> _removeServer(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Server'),
        content: Text('Are you sure you want to remove "${server.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SecureKeyStore.deleteApiKey(server.name);
    } catch (_) {}

    final db = ref.read(nexusDatabaseProvider);
    final currentClientId = ref.read(currentClientIdProvider);
    final rows = await db.getInferenceServersForClient(currentClientId);

    final row = rows.firstWhere(
      (r) => r.name == server.name,
      orElse: () => throw Exception('Server not found'),
    );

    await (db.delete(
      db.inferenceServers,
    )..where((s) => s.server_pk.equals(row.server_pk))).go();

    ref.invalidate(lemonadeServersProvider);

    if (ref.read(selectedLemonadeServerProvider)?.name == server.name) {
      ref.read(selectedLemonadeServerProvider.notifier).selectServer(null);
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Server "${server.name}" removed.')));
  }
}
