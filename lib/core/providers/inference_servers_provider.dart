// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/inference_server.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'inference_servers_provider.g.dart';

/// @deprecated
/// This global notifier has been replaced by client-scoped Drift storage
/// (see inferenceServersForClientProvider in database_provider.dart).
///
/// It is kept only for backward compatibility with any remaining references
/// during the multi-tenancy migration. New code should use the Drift-backed,
/// client-scoped providers instead.
@riverpod
class InferenceServersNotifier extends _$InferenceServersNotifier {
  @override
  List<InferenceServer> build() {
    // Legacy seed data - no longer used for the main Agents Hub UI.
    return [
      InferenceServer(
        id: 'legacy-local-lemonade',
        name: 'Local Lemonade (legacy)',
        baseUrl: 'http://localhost:13305/v1',
        providerType: 'lemonade',
        maxConcurrency: 3,
        maxAgents: 6,
      ),
    ];
  }

  void addServer(InferenceServer server) {
    state = [...state, server];
  }

  void updateServer(InferenceServer updated) {
    state = state.map((s) => s.id == updated.id ? updated : s).toList();
  }

  void removeServer(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  void setSelectedModel(String serverId, String modelId) {
    state = state.map((s) {
      if (s.id == serverId) {
        return s.copyWith(selectedModel: modelId);
      }
      return s;
    }).toList();
  }

  void updateAvailableModels(String serverId, List<String> models) {
    state = state.map((s) {
      if (s.id == serverId) {
        return s.copyWith(availableModels: models);
      }
      return s;
    }).toList();
  }

  InferenceServer? getServerById(String id) {
    try {
      return state.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}
