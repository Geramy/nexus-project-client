// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:nexus_projects_client/infrastructure/lemonade/services/persona_model_resolver.dart'
    show kDefaultOmniCollection;

/// The model the coordinator should use. [collection]/[chat] are the SAME here:
/// the product's default Omni collection id (LMX-Omni-52B-Halo) is addressed
/// DIRECTLY — exactly like the app (which sends the inference server's
/// `selectedModel` straight to the Nexus Router, which serves the collection).
class ResolvedCoordinatorModel {
  ResolvedCoordinatorModel(this.collection, this.chat);
  final String collection;
  final String chat;
}

/// Use the product's default Omni collection (`LMX-Omni-52B-Halo`) directly, or
/// an explicit [override] (the NEXUS_MODEL secret). We deliberately do NOT
/// decompose the collection into a sub-component: the routed gateway serves the
/// collection id itself, and decomposing it fell through to the first raw text
/// model (a 4B) — which is NOT what the app sends. [gateway]/[token] are unused
/// now (kept for call-site compatibility).
Future<ResolvedCoordinatorModel> resolveCoordinatorModel({
  required String gateway,
  required String token,
  String? override,
}) async {
  final ov = override?.trim();
  final id = (ov != null && ov.isNotEmpty) ? ov : kDefaultOmniCollection;
  return ResolvedCoordinatorModel(id, id);
}

/// Shared by the live E2E tests: choose a TEXT/chat model from a routed catalog.
///
/// The router serves mixed modalities (e.g. `SD-Turbo` is an image model that
/// 503s a chat call), so we cannot just take `models.first`. Resolution order:
///   1. an explicit [override] (the optional NEXUS_MODEL secret), if present
///      in the catalog (case-insensitive) — or used verbatim if the catalog
///      can't confirm it (operator knows best);
///   2. the first model whose id matches a known LLM family (llama/qwen/…);
///   3. the first model that is NOT obviously image/audio/embedding/vision;
///   4. as a last resort, the first model (keeps the test running rather than
///      failing on an empty pick).
String pickTextModel(List<String> ids, String? override) {
  if (ids.isEmpty) return '';

  final ov = override?.trim();
  if (ov != null && ov.isNotEmpty) {
    final hit = ids.firstWhere(
      (id) => id.toLowerCase() == ov.toLowerCase(),
      orElse: () => '',
    );
    return hit.isNotEmpty ? hit : ov;
  }

  // Non-text modalities to skip when auto-picking.
  const nonText = [
    'turbo', 'stable', 'diffusion', 'sdxl', 'sd-', 'flux', 'dall', 'imagen',
    'whisper', 'tts', 'stt', 'voice', 'audio', 'speech',
    'embed', 'rerank', 'bge', 'vision', 'image', 'video', 'clip',
  ];
  // Known text/LLM families to prefer.
  const llm = [
    'llama', 'qwen', 'mistral', 'mixtral', 'gemma', 'phi', 'deepseek', 'glm',
    'gpt', 'claude', 'instruct', 'chat', 'yi', 'command', 'nemo', 'hermes',
  ];

  bool isNonText(String id) {
    final l = id.toLowerCase();
    return nonText.any(l.contains);
  }

  final preferred = ids.firstWhere(
    (id) => !isNonText(id) && llm.any(id.toLowerCase().contains),
    orElse: () => '',
  );
  if (preferred.isNotEmpty) return preferred;

  final anyText = ids.firstWhere((id) => !isNonText(id), orElse: () => '');
  if (anyText.isNotEmpty) return anyText;

  return ids.first;
}
