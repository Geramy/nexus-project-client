// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../../infrastructure/inference/inference_backend.dart';
import '../../infrastructure/inference/inference_backend_factory.dart'
    show backendForServer;
import '../../infrastructure/inference/routed_server.dart'
    show isRoutedProviderType;
import '../../features/agents/agent_role.dart';
import '../../features/agents/thinking_mode.dart';
import '../../infrastructure/lemonade/services/persona_model_resolver.dart';
import '../../infrastructure/models/ui/inference_server.dart' as ui_server;
import '../../features/ai_providers/providers/ai_servers_cache_provider.dart';

/// A resolved inference backend + chat model for a project, mirroring how the
/// Coordinator chat picks the agent's server. Used by the Setup interview and
/// the Summary compiler so they talk to the same backend as the Coordinator.
class ResolvedInference {
  const ResolvedInference({
    required this.backend,
    required this.model,
    this.sttModel,
    this.ttsModel,
    this.ttsVoice,
    this.enableThinking,
  });
  final InferenceBackend backend;
  final String model;

  /// Effective enable_thinking for the project agent (null omits the param).
  final bool? enableThinking;

  /// Per-modality models for voice "call mode" in the Setup interview. Null
  /// falls back to the server/default at the audio endpoints.
  final String? sttModel;
  final String? ttsModel;
  final String? ttsVoice;
}

/// Resolves the backend the project's Coordinator agent is connected to (or the
/// client's first server), plus the best chat model. Yields null when no
/// inference servers are configured for the client. Exposed as a provider so
/// both [WidgetRef] (Setup tab) and [Ref] (SummaryService) can read it.
final projectInferenceProvider = FutureProvider.family<ResolvedInference?, ({int projectId, int clientId})>((
  ref,
  args,
) async {
  // WATCH (not read) the server stream so this re-resolves whenever the configs
  // change — critically when router_server_sync rewrites the routed server's
  // apiKey after a re-login. Reading once cached a backend with a baked,
  // never-refreshed token, which is why the Setup interview kept 401-ing on STT
  // while the Coordinator (which rebuilds its client on every open) worked.
  final servers = await ref.watch(
    inferenceServersForClientProvider(args.clientId).future,
  );
  if (servers.isEmpty) return null;

  final db = ref.read(nexusDatabaseProvider);

  // Setup is hosted by the PROJECT MANAGER agent — resolve it by role so the
  // interview always runs as the PM (and gets its NXS-PJX-Interview collection),
  // regardless of the project's single assigned-agent FK.
  dynamic persona;
  try {
    final personaId =
        await db.getProjectRolePersonaId(
          args.projectId,
          AgentRole.projectManager.key,
        ) ??
        await db.getProjectAgentPersonaId(args.projectId);
    if (personaId != null) persona = await db.resolveAgentPersona(personaId);
  } catch (_) {}

  // Default to the Nexus Router (subscription) server when it exists — its
  // presence means the user is signed in. An agent's explicit provider_fk still
  // wins below.
  var chosen = servers.firstWhere(
    (s) => isRoutedProviderType(s.providerType),
    orElse: () => servers.first,
  );
  if (persona?.provider_fk != null) {
    for (final s in servers) {
      if (s.server_pk == persona.provider_fk) {
        chosen = s;
        break;
      }
    }
  }

  final models = chosen.availableModelsJson.isNotEmpty
      ? (jsonDecode(chosen.availableModelsJson) as List).cast<String>()
      : const <String>[];

  final cache = ref.read(aiServersCacheProvider.notifier);
  var entry = cache.entryFor(chosen.server_pk);
  if (entry == null || entry.models.isEmpty) {
    await cache.refreshServer(chosen.server_pk);
    entry = cache.entryFor(chosen.server_pk);
  }
  final serverModels = entry?.models ?? const [];

  String? sttModel;
  String? ttsModel;
  String? ttsVoice = persona?.ttsVoice as String?;

  // The Setup interview uses the Project Manager agent's Omni collection
  // (NXS-PJX-Interview by default), falling back to the role default when the
  // persona hasn't stored one. Resolve its STT/TTS components for voice.
  final personaCollection = persona?.omniCollectionModel as String?;
  final omniCollection =
      (personaCollection != null && personaCollection.trim().isNotEmpty)
      ? personaCollection.trim()
      : defaultOmniCollectionForTitle(persona?.title as String?);
  if (omniCollection.isNotEmpty) {
    final resolved = resolvePersonaModels(
      omniCollectionModel: omniCollection,
      llmModel: persona?.llmModel as String?,
      sttModel: persona?.sttModel as String?,
      ttsModel: persona?.ttsModel as String?,
      visionModel: persona?.visionModel as String?,
      imageGenModel: persona?.imageGenModel as String?,
      models: serverModels,
    );
    sttModel = resolved.stt;
    ttsModel = resolved.tts;
  }
  // Safety net (any path, incl. no persona): never let voice fall back to the
  // backend's `whisper-1` / empty TTS defaults, which 404 on Lemonade servers.
  // Resolve the server's own transcription/speech models instead.
  sttModel ??= firstAudioModelId(serverModels);
  ttsModel ??= firstTtsModelId(serverModels);

  // The routed Nexus Router serves the Omni COLLECTION id directly, so send the
  // PM agent's Interview collection (or an explicit per-persona model) as-is — do
  // NOT decompose to a raw sub-model (which fell through to a small 4B: the wrong
  // model). Local servers (which 500 on a bare collection) decompose from the
  // live list. STT/TTS components are still resolved above for voice.
  final routed = isRoutedProviderType(chosen.providerType);
  final personaModel = persona?.llmModel as String?;
  final model = routed
      ? ((personaModel != null && personaModel.trim().isNotEmpty)
            ? personaModel.trim()
            : omniCollection)
      : resolveAgentChatModel(
          routed: false,
          personaModel: personaModel,
          selectedModel: chosen.selectedModel,
          serverModels: serverModels,
        );

  final uiServer = ui_server.InferenceServer(
    id: chosen.server_pk.toString(),
    name: chosen.name,
    baseUrl: chosen.baseUrl,
    apiKey: chosen.apiKey,
    providerType: 'lemonade',
    selectedModel: chosen.selectedModel,
    availableModels: models,
  );

  return ResolvedInference(
    backend: backendForServer(uiServer),
    model: model,
    sttModel: sttModel,
    ttsModel: ttsModel,
    ttsVoice: ttsVoice,
    // Agent-level thinking mode (Project Manager defaults Off, others Unset).
    enableThinking: resolveEnableThinking(
      agent: personaThinkingMode(
        persona?.configJson as String?,
        personaName: persona?.name as String?,
      ),
    ),
  );
});
