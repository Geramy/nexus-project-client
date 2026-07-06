// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:nexus_projects_client/infrastructure/lemonade/api/types/model_info.dart';

/// The product's default Omni Collection. Seeded onto the built-in personas and
/// used as the preferred fallback when a persona (or server) hasn't picked a
/// collection, so voice/vision/image work out of the box. Decomposes into its
/// component STT/TTS/LLM models via [resolvePersonaModels].
///
/// IMPORTANT: this MUST match the collection `id` the Nexus Router advertises
/// exactly (case + spacing). The router serves the collection id as-is, so a
/// mismatch sends an unknown id. When the server renames a collection, update
/// this AND add the old id to [kRetiredOmniCollections] so existing personas are
/// migrated off it on next launch.
const String kDefaultOmniCollection = 'NXS-PJX-Chat';

/// Collection ids that were retired/renamed server-side. Any persona still
/// pointing at one of these is migrated to its role-appropriate default on
/// launch (see the seeder), so existing projects don't keep sending a model id
/// the router no longer serves.
const List<String> kRetiredOmniCollections = <String>['LMX-Omni-52B-Halo'];

/// The Setup interview's default Omni collection — used by the **Project Manager**
/// agent that hosts the setup screen.
const String kInterviewOmniCollection = 'NXS-PJX-Interview';

/// The Discovery / user-story default Omni collection — used by the **Coordinator**
/// agent that hosts the user-story screen.
const String kDiscoveryOmniCollection = 'NXS-PJX-Discovery';

/// The default Omni collection for a persona, keyed by its role `title`
/// (the `AgentRole.key` stored in the personas table):
///   • `projectManager` → [kInterviewOmniCollection]
///   • `coordinator`    → [kDiscoveryOmniCollection]
///   • everything else  → [kDefaultOmniCollection]
/// Keep these keys in sync with `AgentRole.key`.
String defaultOmniCollectionForTitle(String? title) {
  switch (title) {
    case 'projectManager':
      return kInterviewOmniCollection;
    case 'coordinator':
      return kDiscoveryOmniCollection;
    default:
      return kDefaultOmniCollection;
  }
}

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
    final want = explicit ?? selected ?? kDefaultOmniCollection;
    // Resolve BY TAGS when the live catalog is known: a collection is decomposed
    // to its chat/LLM component (see [resolveRoutedChatModel]) so we never send
    // the bare collection id and let the router land on a non-chat component like
    // the embedding model (→ HTTP 400 "does not support chat completion"). When
    // the catalog doesn't advertise `want` at all (e.g. a renamed collection),
    // self-heal to an advertised collection's chat model. Empty catalog = "don't
    // know" → trust the configured id as-is.
    if (serverModels.isNotEmpty) {
      final direct = resolveRoutedChatModel(want, serverModels);
      if (direct != null) return direct;
      final alt = defaultOmniCollectionId(serverModels);
      if (alt != null) {
        return resolveRoutedChatModel(alt, serverModels) ?? alt;
      }
    }
    return want;
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

/// The BEST plain chat/LLM model on the server (not a collection, not an
/// audio/tts/image-only model — those 500 on chat). Prefers the higher-quality
/// model over catalog order. Falls back to any non-collection.
String? firstChatModelId(List<ApiModelInfo> models) {
  final best = _bestModelId(
    models,
    (m) => !_isAudio(m) && !_isTts(m) && !_isImageGen(m),
  );
  if (best != null) return best;
  for (final m in models) {
    if (!m.isCollection) return m.id;
  }
  return null;
}

/// The BEST transcription/audio (STT) model on the server, or null. Safety net
/// so a voice turn never sends OpenAI's `whisper-1` (which Lemonade servers 404
/// on) when a persona/collection didn't resolve an STT model. Prefers quality
/// (e.g. Whisper-Large-v3 over Whisper-Tiny) — NOT catalog order. ("turbo" is
/// fine for STT, e.g. large-v3-turbo, so it isn't penalized here.)
String? firstAudioModelId(List<ApiModelInfo> models) =>
    _bestModelId(models, _isAudio);

/// The BEST text-to-speech (TTS) model on the server, or null. Safety net so a
/// spoken reply never posts an empty model id (which 404s) when nothing resolved.
String? firstTtsModelId(List<ApiModelInfo> models) =>
    _bestModelId(models, _isTts);

/// The BEST image-generation model on the server, or null. Safety net so a
/// diagram/image request never posts an empty model id (which the router 502s on
/// — "All candidate backends failed") when a persona/collection didn't resolve
/// an image model. Prefers quality over catalog order so a fallback picks Flux/
/// SDXL ahead of a lite model like SD-Turbo (turbo IS penalized for image).
String? firstImageModelId(List<ApiModelInfo> models) =>
    _bestModelId(models, _isImageGen, turboIsBad: true);

/// Pick the highest-quality non-collection model matching [test], by a heuristic
/// score (penalize tiny/mini/lite/etc., reward large/xl/flux/v3). Ties keep
/// catalog order (stable). Null when nothing matches.
String? _bestModelId(
  List<ApiModelInfo> models,
  bool Function(ApiModelInfo) test, {
  bool turboIsBad = false,
}) {
  ApiModelInfo? best;
  var bestScore = -1 << 30;
  for (final m in models) {
    if (m.isCollection) continue;
    if (!test(m)) continue;
    final s = _qualityScore(m.id, turboIsBad: turboIsBad);
    if (best == null || s > bestScore) {
      best = m;
      bestScore = s;
    }
  }
  return best?.id;
}

/// Rough quality score from a model id: low-tier markers (tiny/nano/mini/lite/
/// small/base) drag it down; high-tier markers (large/xl/sdxl/flux/v3/medium)
/// lift it. [turboIsBad] additionally penalizes "turbo" (right for image —
/// SD-Turbo is the lite one — but not for STT, where large-v3-turbo is best).
int _qualityScore(String id, {bool turboIsBad = false}) {
  final l = id.toLowerCase();
  var s = 0;
  for (final t in const ['tiny', 'nano']) {
    if (l.contains(t)) s -= 3;
  }
  for (final t in const ['mini', 'lite']) {
    if (l.contains(t)) s -= 2;
  }
  for (final t in const ['small', 'base']) {
    if (l.contains(t)) s -= 1;
  }
  if (turboIsBad && l.contains('turbo')) s -= 3;
  for (final t in const ['large', 'sdxl', 'flux', 'huge']) {
    if (l.contains(t)) s += 2;
  }
  for (final t in const ['xl', 'v3', 'medium']) {
    if (l.contains(t)) s += 1;
  }
  return s;
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

/// Best routed collection id from a PLAIN advertised-id list (the routed server's
/// `availableModelsJson`, which has no collection/labels metadata). Used to
/// self-heal when the configured collection isn't advertised (a server-side
/// rename): prefer an id that looks like the chat/omni collection, and never
/// guess a random raw model. Null when nothing suitable is advertised.
String? pickRoutedCollectionId(List<String> advertised) {
  for (final id in advertised) {
    final l = id.toLowerCase();
    if (l.contains('omni') || l.contains('chat')) return id;
  }
  return null;
}

bool _nameHasAny(String id, List<String> needles) {
  final l = id.toLowerCase();
  return needles.any(l.contains);
}

// Capability classification — label-first, then name heuristics, matching
// lemonade_mobile's ModelUtils.detectCapabilities label conventions.
bool _isAudio(ApiModelInfo m) =>
    m.hasAnyLabel(const ['audio', 'transcription', 'realtime-transcription']) ||
    _nameHasAny(m.id, const ['whisper', 'transcrib', 'moonshine']);
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
bool _isEmbedding(ApiModelInfo m) =>
    m.hasAnyLabel(const ['embedding', 'embeddings', 'embed']) ||
    _nameHasAny(m.id, const ['embedding', 'embed', 'bge', 'gte']);

/// The chat/LLM component of a collection, chosen BY TAGS. A collection bundles
/// several models (chat, embedding, tts, stt, image); the chat endpoint only
/// accepts the LLM one — sending the bare collection id lets the router pick a
/// component itself, and it can land on the EMBEDDING model → HTTP 400 "this
/// model does not support chat completion". So resolve it here: prefer a
/// component positively tagged chat/text/llm, else the first that ISN'T
/// audio/tts/image/embedding (a vision-capable multimodal LLM is a valid chat
/// model). Returns null if [collection] isn't a decomposable collection.
String? chatComponentIdOf(ApiModelInfo collection, List<ApiModelInfo> catalog) {
  if (!collection.isCollection) return null;
  final comps = <ApiModelInfo>[
    for (final cid in collection.compositeModels)
      catalog.firstWhere(
        (m) => m.id == cid,
        orElse: () => ApiModelInfo(id: cid, labels: const []),
      ),
  ];
  // EXCLUDE the non-chat modalities FIRST — embedding especially. (The embedding
  // model is often listed first AND carries generic labels like 'text', so a
  // label-first pick wrongly chose it → HTTP 400 "does not support chat".) A
  // vision-capable multimodal LLM is still a valid chat model, so vision is kept.
  final chatCandidates = comps
      .where(
        (c) =>
            !_isAudio(c) &&
            !_isTts(c) &&
            !_isImageGen(c) &&
            !_isEmbedding(c),
      )
      .toList();
  final pool = chatCandidates.isNotEmpty ? chatCandidates : comps;
  // Among the survivors, prefer one explicitly tagged as a chat/LLM (NOT the
  // broad 'text', which embeddings also use).
  for (final c in pool) {
    if (c.hasAnyLabel(const [
      'chat',
      'llm',
      'text-generation',
      'chat-completion',
      'instruct',
      'reasoning',
    ])) {
      return c.id;
    }
  }
  return pool.isNotEmpty ? pool.first.id : null;
}

/// Resolve an id to send to the CHAT endpoint on a ROUTED server. If [idOrModel]
/// is a collection in [catalog], returns its chat/LLM component (see
/// [chatComponentIdOf]); if it's already a concrete model, returns it; null when
/// the id isn't in the catalog at all (caller decides the fallback).
String? resolveRoutedChatModel(String idOrModel, List<ApiModelInfo> catalog) {
  ApiModelInfo? entry;
  for (final m in catalog) {
    if (m.id == idOrModel) {
      entry = m;
      break;
    }
  }
  if (entry == null) return null;
  if (!entry.isCollection) return idOrModel;
  return chatComponentIdOf(entry, catalog) ?? idOrModel;
}

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

  String? stt, tts, vision, imageGen;
  for (final c in components) {
    if (stt == null && _isAudio(c)) stt = c.id;
    if (tts == null && _isTts(c)) tts = c.id;
    if (vision == null && _isVision(c)) vision = c.id;
    if (imageGen == null && _isImageGen(c)) imageGen = c.id;
  }
  // LLM/chat = the chat-tagged component, else the first that isn't audio/tts/
  // image/EMBEDDING (excluding embedding is what was missing — the embedding
  // model was being picked as "chat" and 400'ing). Vision-multimodal LLMs count.
  final llm = chatComponentIdOf(collection, models) ?? components.first.id;

  return ResolvedModalityModels(
    llm: llm,
    stt: stt,
    tts: tts,
    vision: vision,
    imageGen: imageGen,
  );
}
