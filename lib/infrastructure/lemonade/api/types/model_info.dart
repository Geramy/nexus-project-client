// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Ported exactly from ~/IdeaProjects/lemonade_mobile/lib/api/types/model_info.dart
/// Wire-format model entry from `GET /v1/models` (with `?show_all=true` to include collections).
class ApiModelInfo {
  final String id;
  final List<String> labels;
  final String? recipe;
  final List<String> compositeModels;
  final bool? downloaded;
  final String? checkpoint;
  final bool suggested;

  ApiModelInfo({
    required this.id,
    required this.labels,
    this.recipe,
    this.compositeModels = const [],
    this.downloaded,
    this.checkpoint,
    this.suggested = false,
  });

  /// True when this is a Lemonade Omni Model — a bundle whose `recipe` is
  /// `collection.omni` and which lists its component models. This is the
  /// authoritative server signal for "this model is an Omni / tool-calling
  /// bundle".
  bool get isCollection =>
      (recipe == 'collection.omni' || recipe == 'collection') &&
      compositeModels.isNotEmpty;

  /// Returns true if this model has at least one of the requested labels.
  bool hasAnyLabel(Iterable<String> requested) {
    if (labels.isEmpty) return false;
    final wanted = requested.toSet();
    return labels.any(wanted.contains);
  }

  factory ApiModelInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final rawLabels = json['labels'];
    final labels = rawLabels is List
        ? rawLabels.whereType<String>().toList()
        : <String>[];
    final rawComponents = json['components'] ?? json['composite_models'];
    final composite = rawComponents is List
        ? rawComponents.whereType<String>().toList()
        : <String>[];

    return ApiModelInfo(
      id: id,
      labels: labels,
      recipe: json['recipe'] as String?,
      compositeModels: composite,
      downloaded: json['downloaded'] as bool?,
      checkpoint: json['checkpoint'] as String?,
      suggested: json['suggested'] as bool? ?? false,
    );
  }
}
