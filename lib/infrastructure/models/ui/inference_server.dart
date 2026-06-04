// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

class InferenceServer {
  final String id;
  final String name;
  final String
  baseUrl; // e.g. http://localhost:13305/v1 or https://api.openai.com/v1
  final String apiKey; // Can be empty for local servers
  final String providerType; // 'lemonade', 'openai', 'ollama', 'custom', etc.

  // Resource limits (user requirement)
  final int maxConcurrency;
  final int maxAgents;

  final bool isEnabled;
  final String? selectedModel; // The model the user has chosen for this server
  final List<String> availableModels; // Cached list from last refresh
  final Map<String, dynamic>
  extraConfig; // For future things like headers, timeouts, etc.
  final Map<String, dynamic>
  capabilities; // Probed API capabilities e.g. {"models": true, "modelsSupportsShowAll": true, "isLemonade": true, "audioTranscription": true, ...}

  const InferenceServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.providerType = 'custom',
    this.maxConcurrency = 4,
    this.maxAgents = 8,
    this.isEnabled = true,
    this.selectedModel,
    this.availableModels = const [],
    this.extraConfig = const {},
    this.capabilities = const {},
  });

  InferenceServer copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? providerType,
    int? maxConcurrency,
    int? maxAgents,
    bool? isEnabled,
    String? selectedModel,
    List<String>? availableModels,
    Map<String, dynamic>? extraConfig,
    Map<String, dynamic>? capabilities,
  }) {
    return InferenceServer(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      providerType: providerType ?? this.providerType,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      maxAgents: maxAgents ?? this.maxAgents,
      isEnabled: isEnabled ?? this.isEnabled,
      selectedModel: selectedModel ?? this.selectedModel,
      availableModels: availableModels ?? this.availableModels,
      extraConfig: extraConfig ?? this.extraConfig,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'providerType': providerType,
    'maxConcurrency': maxConcurrency,
    'maxAgents': maxAgents,
    'isEnabled': isEnabled,
    'selectedModel': selectedModel,
    'availableModels': availableModels,
    'extraConfig': extraConfig,
    'capabilities': capabilities,
  };

  factory InferenceServer.fromJson(Map<String, dynamic> json) =>
      InferenceServer(
        id: json['id'],
        name: json['name'],
        baseUrl: json['baseUrl'],
        apiKey: json['apiKey'] ?? '',
        providerType: json['providerType'] ?? 'custom',
        maxConcurrency: json['maxConcurrency'] ?? 4,
        maxAgents: json['maxAgents'] ?? 8,
        isEnabled: json['isEnabled'] ?? true,
        selectedModel: json['selectedModel'],
        availableModels: List<String>.from(json['availableModels'] ?? []),
        extraConfig: Map<String, dynamic>.from(json['extraConfig'] ?? {}),
        capabilities: Map<String, dynamic>.from(json['capabilities'] ?? {}),
      );
}
