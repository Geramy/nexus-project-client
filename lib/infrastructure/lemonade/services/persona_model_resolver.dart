// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:nexus_projects_client/infrastructure/lemonade/api/types/model_info.dart';

/// The product's default Omni Collection. Seeded onto the built-in personas and
/// used as the preferred fallback when a persona (or server) hasn't picked a
/// collection, so voice/vision/image work out of the box. Decomposes into its
/// component STT/TTS/LLM models via [resolvePersonaModels].
const String kDefaultOmniCollection = 'LMX-Omni-52B-Halo';

/// The concrete model id to use for each modality, resolved from a persona's
/// saved configuration.
///
/// When the persona has an Omni Collection selected, each modality is resolved
/// to the collection's component model whose labels/name indicate that
/// capability — mirroring how lemonade_mobile decomposes a `collection.omni`
/// into per-tool model ids. When no collection is selected, the persona's
/// individually-selected models are used. Any field may be null when the
/// persona/collection doesn't provide that modality.
class ResolvedModalityModels {
  final String? llm;
  final String? stt;
  final String? tts;
  final String? vision;
  final String? imageGen;

  const ResolvedModalityModels({
    this.llm,
    this.stt,
    this.tts,
    this.vision,
    this.imageGen,
  });

  @override
  String toString() =>
      'ResolvedModalityModels(llm: $llm, stt: $stt, tts: $tts, vision: $vision, imageGen: $imageGen)';
}

String? _emptyToNull(String? s) =>
    (s != null && s.trim().isNotEmpty) ? s.trim() : null;

/// The chat/LLM model id an agent (coordinator, worker, verifier, task-gen…)
/// should send, honoring the two serving models in play:
///  • the ROUTED Nexus Router serves the Omni-COLLECTION id directly, so we send
///    it as-is and default to it. Decomposing the collection fell through to the
///    first raw text model (a small 4B, e.g. Qwen3.5-4B) — the WRONG model.
///  • a LOCAL Lemonade server 500s on a bare collection id, so there we decompose
///    to a real chat model from the live [serverModels] list.
///
/// Priority: an explicit per-persona [personaModel] → the server's
/// [selectedModel] → the product default Omni collection [kDefaultOmniCollection]
/// (routed) / the first served chat model (local). Never returns empty.
String resolveAgentChatModel({
  required bool routed,
  String? personaModel,
  String? selectedModel,
  List<ApiModelInfo> serverModels = const [],
}) {
  final explicit = _emptyToNull(personaModel);
  final selected = _emptyToNull(selectedModel);
  if (routed) {
    // Send the configured id straight to the router (it serves the collection);
    // default to the product Omni collection. No decomposition.
    return explicit ?? selected ?? kDefaultOmniCollection;
  }
  final candidate = explicit ?? selected ?? firstChatModelId(serverModels);
  return resolveChatModelId(candidate, serverModels) ?? candidate ?? kDefaultOmniCollection;
}

/// Coerce any candidate model id into a safe chat/LLM model id to send to
/// `/v1/chat/completions`. If [candidate] is an Omni Collection, decompose it
/// to its LLM component (collections are not loadable chat models — the server
/// 500s on them). Falls back to the first real chat model on the server when
/// the candidate is empty or an undecomposable collection.
String? resolveChatModelId(String? candidate, List<ApiModelInfo> models) {
  final id = _emptyToNull(candidate);
  if (id == null) return firstChatModelId(models);
  for (final m in models) {
    if (m.id != id) continue;
    if (m.isCollection) {
      final llm = resolvePersonaModels(
        omniCollectionModel: id,
        models: models,
      ).llm;
      return (llm != null && llm != id) ? llm : firstChatModelId(models);
    }
    return id; // a plain, loadable model that exists on the server
  }
  return id; // not in the (possibly stale) list — trust it as-is
}

/// First plain chat/LLM model id from a server list: not a collection and not
/// an audio/tts/image-only model (so we don't accidentally send chat requests
/// to Whisper/TTS/diffusion models, which 500). Falls back to any non-collection.
String? firstChatModelId(List<ApiModelInfo> models) {
  for (final m in models) {
    if (m.isCollection) continue;
    if (_isAudio(m) || _isTts(m) || _isImageGen(m)) continue;
    return m.id;
  }
  for (final m in models) {
    if (!m.isCollection) return m.id;
  }
  return null;
}

/// First transcription/audio (STT) model id on the server, or null. Used as the
/// safety net so a voice turn never sends OpenAI's `whisper-1` (which Lemonade
/// servers 404 on) when a persona/collection didn't resolve an STT model.
String? firstAudioModelId(List<ApiModelInfo> models) {
  for (final m in models) {
    if (m.isCollection) continue;
    if (_isAudio(m)) return m.id;
  }
  return null;
}

/// First text-to-speech (TTS) model id on the server, or null. Safety net so a
/// spoken reply never posts an empty model id (which 404s) when nothing resolved.
String? firstTtsModelId(List<ApiModelInfo> models) {
  for (final m in models) {
    if (m.isCollection) continue;
    if (_isTts(m)) return m.id;
  }
  return null;
}

/// The Omni Collection id to use when a persona hasn't chosen one: the product
/// default [kDefaultOmniCollection] if the server advertises it, otherwise the
/// first collection the server lists. Null when the server exposes none.
String? defaultOmniCollectionId(List<ApiModelInfo> models) {
  ApiModelInfo? first;
  for (final m in models) {
    if (!m.isCollection) continue;
    first ??= m;
    if (m.id == kDefaultOmniCollection) return m.id;
  }
  return first?.id;
}

bool _nameHasAny(String id, List<String> needles) {
  final l = id.toLowerCase();
  return needles.any(l.contains);
}

// Capability classification — label-first, then name heuristics, matching
// lemonade_mobile's ModelUtils.detectCapabilities label conventions.
bool _isAudio(ApiModelInfo m) =>
    m.hasAnyLabel(const ['audio', 'transcription']) ||
    _nameHasAny(m.id, const ['whisper', 'transcrib']);
bool _isTts(ApiModelInfo m) =>
    m.hasAnyLabel(const ['tts', 'speech']) ||
    _nameHasAny(m.id, const ['tts', 'kokoro']);
bool _isVision(ApiModelInfo m) =>
    m.hasAnyLabel(const ['vision']) ||
    _nameHasAny(m.id, const ['vision', 'llava', 'moondream', 'internvl']) ||
    (m.id.toLowerCase().contains('qwen') && m.id.toLowerCase().contains('vl'));
bool _isImageGen(ApiModelInfo m) =>
    m.hasAnyLabel(const ['image', 'generation']) ||
    _nameHasAny(m.id, const ['dall', 'stable-diffusion', 'sdxl', 'flux']);

/// Resolve the per-modality model ids for a persona.
///
/// [models] is the server's full model list (collections + individual models,
/// i.e. `GET /v1/models?show_all=true`). Pass the persona's saved fields.
ResolvedModalityModels resolvePersonaModels({
  String? omniCollectionModel,
  String? llmModel,
  String? sttModel,
  String? ttsModel,
  String? visionModel,
  String? imageGenModel,
  required List<ApiModelInfo> models,
}) {
  final omniId = _emptyToNull(omniCollectionModel);

  if (omniId == null) {
    // No collection: use the individually-selected models verbatim.
    return ResolvedModalityModels(
      llm: _emptyToNull(llmModel),
      stt: _emptyToNull(sttModel),
      tts: _emptyToNull(ttsModel),
      vision: _emptyToNull(visionModel),
      imageGen: _emptyToNull(imageGenModel),
    );
  }

  // Collection selected: decompose it into its component models.
  ApiModelInfo? collection;
  for (final m in models) {
    if (m.id == omniId) {
      collection = m;
      break;
    }
  }

  if (collection == null || collection.compositeModels.isEmpty) {
    // Can't decompose from the (stale/empty) model list. Never route chat at
    // the bare collection id — the server 500s on it ("type must be a string,
    // but is null"). Prefer any component model the editor already persisted;
    // otherwise leave llm null so the caller picks a real chat model.
    final savedLlm = _emptyToNull(llmModel);
    return ResolvedModalityModels(
      llm: savedLlm == omniId ? null : savedLlm,
      stt: _emptyToNull(sttModel),
      tts: _emptyToNull(ttsModel),
      vision: _emptyToNull(visionModel),
      imageGen: _emptyToNull(imageGenModel),
    );
  }

  // Look up each component id to get its labels.
  final components = <ApiModelInfo>[];
  for (final cid in collection.compositeModels) {
    ApiModelInfo? found;
    for (final m in models) {
      if (m.id == cid) {
        found = m;
        break;
      }
    }
    components.add(found ?? ApiModelInfo(id: cid, labels: const []));
  }

  String? stt, tts, vision, imageGen, llm;
  for (final c in components) {
    if (stt == null && _isAudio(c)) stt = c.id;
    if (tts == null && _isTts(c)) tts = c.id;
    if (vision == null && _isVision(c)) vision = c.id;
    if (imageGen == null && _isImageGen(c)) imageGen = c.id;
  }
  // LLM/chat = first component that isn't a pure audio/tts/image-gen model
  // (vision-capable multimodal LLMs are valid chat models).
  for (final c in components) {
    if (!_isAudio(c) && !_isTts(c) && !_isImageGen(c)) {
      llm = c.id;
      break;
    }
  }
  llm ??= components.first.id;

  return ResolvedModalityModels(
    llm: llm,
    stt: stt,
    tts: tts,
    vision: vision,
    imageGen: imageGen,
  );
}
