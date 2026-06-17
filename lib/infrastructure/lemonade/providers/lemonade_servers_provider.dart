// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Adapted port from ~/IdeaProjects/lemonade_mobile/lib/providers/servers_provider.dart
///
/// This version unifies on the existing Nexus Drift database (InferenceServers table)
/// instead of introducing a second Isar DB. Only rows that are detected as full
/// local Lemonade servers (omni collections / admin endpoints) get the rich
/// server management infrastructure (ServersScreen + AdminConsole).
///
/// Routed/routed servers (nexus-projects-server) continue to use the lighter
/// EndpointsTab + ServerConfigDialog path and are never presented through this provider.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show InferenceServersCompanion;

import '../models/server_config.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/app_shell_provider.dart';
import '../services/secure_key_store.dart';

/// The list of configured Lemonade servers (only those that qualified as full local mgmt).
/// This is a derived view over the existing Drift InferenceServers (providerType == 'lemonade'
/// or capabilities indicate full admin + omni support).
final lemonadeServersProvider =
    StateNotifierProvider<LemonadeServersNotifier, List<ServerConfig>>(
      (ref) => LemonadeServersNotifier(ref),
    );

final selectedLemonadeServerProvider =
    StateNotifierProvider<SelectedLemonadeServerNotifier, ServerConfig?>(
      (ref) => SelectedLemonadeServerNotifier(ref),
    );

class LemonadeServersNotifier extends StateNotifier<List<ServerConfig>> {
  final Ref ref;

  LemonadeServersNotifier(this.ref) : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final currentClientId = ref.read(currentClientIdProvider);
      final db = ref.read(nexusDatabaseProvider);
      final rows = await db.getInferenceServersForClient(currentClientId);

      final configs = <ServerConfig>[];
      for (final row in rows) {
        // Only surface servers that are marked as Lemonade (or have the capability flag).
        final caps = _parseCaps(row.capabilitiesJson);
        final isLemonade =
            row.providerType == 'lemonade' ||
            (caps['isLemonade'] == true) ||
            (caps['fullLemonadeManaged'] == true);

        if (!isLemonade) continue;

        String? apiKey;
        if (row.apiKey.isNotEmpty) {
          // Legacy rows may have the key in the DB column — migrate to secure storage on first load.
          apiKey = row.apiKey;
          try {
            await SecureKeyStore.writeApiKey(row.name, row.apiKey);
          } catch (_) {}
        } else {
          try {
            apiKey = await SecureKeyStore.readApiKey(row.name);
          } catch (_) {
            apiKey = null;
          }
        }

        configs.add(
          ServerConfig(name: row.name, baseUrl: row.baseUrl, apiKey: apiKey),
        );
      }
      state = configs;
    } catch (e) {
      debugPrint('LemonadeServersNotifier._load error: $e');
      state = [];
    }
  }

  Map<String, dynamic> _parseCaps(String jsonStr) {
    try {
      if (jsonStr.isEmpty) return {};
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> addServer(ServerConfig server) async {
    try {
      final currentClientId = ref.read(currentClientIdProvider);
      final db = ref.read(nexusDatabaseProvider);

      final hasKey = (server.apiKey ?? '').isNotEmpty;
      if (hasKey) {
        try {
          await SecureKeyStore.writeApiKey(server.name, server.apiKey!);
        } catch (_) {}
      }

      // Persist as a full local Lemonade server row (this makes the page the
      // authoritative source; the server will appear in both AI Providers and
      // the lighter Endpoints list if the user visits Agents Hub).
      final newRow = InferenceServersCompanion.insert(
        client_fk: currentClientId,
        name: server.name,
        baseUrl: server.baseUrl,
        apiKey: const Value(''), // never store plaintext in Drift
        providerType: const Value('lemonade'),
        maxConcurrency: const Value(4),
        maxAgents: const Value(8),
        isEnabled: const Value(true),
        availableModelsJson: const Value('[]'),
        extraConfigJson: const Value('{}'),
        capabilitiesJson: const Value(
          '{"isLemonade":true,"fullLemonadeManaged":true}',
        ),
      );

      await db.createInferenceServer(newRow);

      // Re-sync the in-memory list from the authoritative DB (ensures
      // capabilities + any other fields are loaded consistently).
      await _load();
    } catch (e) {
      debugPrint('LemonadeServersNotifier.addServer error: $e');
    }
  }

  Future<void> removeServer(ServerConfig server) async {
    try {
      await SecureKeyStore.deleteApiKey(server.name);
    } catch (_) {}
    state = state.where((s) => s.name != server.name).toList(growable: false);
  }

  Future<void> updateServer(
    ServerConfig oldServer,
    ServerConfig newServer,
  ) async {
    if (oldServer.name != newServer.name) {
      try {
        await SecureKeyStore.renameApiKey(oldServer.name, newServer.name);
      } catch (_) {}
    }
    if ((newServer.apiKey ?? '').isNotEmpty) {
      try {
        await SecureKeyStore.writeApiKey(newServer.name, newServer.apiKey!);
      } catch (_) {}
    } else {
      try {
        await SecureKeyStore.deleteApiKey(newServer.name);
      } catch (_) {}
    }

    state = state.map((s) => s == oldServer ? newServer : s).toList();
  }
}

class SelectedLemonadeServerNotifier extends StateNotifier<ServerConfig?> {
  final Ref ref;
  String? _savedServerName;

  SelectedLemonadeServerNotifier(this.ref) : super(null) {
    _loadSelected();
    ref.listen(lemonadeServersProvider, (previous, next) {
      if (_savedServerName != null && next.isNotEmpty) {
        state = next.cast<ServerConfig?>().firstWhere(
          (server) => server?.name == _savedServerName,
          orElse: () => null,
        );
      }
    });
  }

  Future<void> _loadSelected() async {
    // For now we auto-select the first Lemonade server (exact match to lemonade_mobile
    // behavior in ServerSelector). Later this can be persisted per-client in app_prefs.
    final servers = ref.read(lemonadeServersProvider);
    if (servers.isNotEmpty) {
      state = servers.first;
      _savedServerName = state?.name;
    }
  }

  Future<void> selectServer(ServerConfig? server) async {
    state = server;
    _savedServerName = server?.name;
  }
}
