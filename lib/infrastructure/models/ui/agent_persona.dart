// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

class AgentPersona {
  final String id;
  final String name;
  final String description;
  final String primaryModel;
  final double costPerMillionTokens;
  final List<String> capabilities;

  // ==================== Prefab Support ====================
  /// True if this is a reusable Prefab (template).
  final bool isPrefab;

  /// If set, this is an instance derived from the given Prefab.
  final String? prefabId;

  /// Whether this instance has local modifications that differ from its prefab.
  final bool hasLocalOverrides;

  // ==================== AI Provider Selection ====================
  /// References the global AI Provider (row in InferenceServers table) that this
  /// persona should use for inference. Null means "use project/client default".
  /// The referenced provider has a providerType (lemonade, grok, openai, etc.)
  /// and a name (often in the form "provider-xxxx").
  final String? aiProviderId;

  // ==================== Omni Collection + Modality Routing ====================
  /// If set, this persona uses an "Omni Collection" model bundle which supplies
  /// all modality models automatically.
  final String? omniCollectionModel;

  /// Individual modality overrides (used when no Omni collection is selected,
  /// or to override specific modalities from an Omni bundle).
  final String? ttsModel; // Text → Voice
  final String? sttModel; // Voice → Text
  final String? imageGenModel; // Image generation
  final String? visionModel; // Image reading / understanding
  final String? llmModel; // Text generation (primary LLM)

  const AgentPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.primaryModel,
    this.costPerMillionTokens = 0.0,
    this.capabilities = const [],
    this.isPrefab = false,
    this.prefabId,
    this.hasLocalOverrides = false,
    this.aiProviderId,
    this.omniCollectionModel,
    this.ttsModel,
    this.sttModel,
    this.imageGenModel,
    this.visionModel,
    this.llmModel,
  });

  bool get isPrefabInstance => prefabId != null;
}
