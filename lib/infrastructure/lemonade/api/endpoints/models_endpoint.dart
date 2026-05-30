// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Ported from ~/IdeaProjects/lemonade_mobile/lib/api/endpoints/models_endpoint.dart
import '../lemonade_client.dart';
import '../types/model_info.dart';

class ModelsEndpoint {
  final LemonadeApiClient _client;
  ModelsEndpoint(this._client);

  /// Returns every model the server knows about, including ones that are
  /// available for download but not yet installed, plus Collections.
  Future<List<ApiModelInfo>> all() => _fetch(showAll: true);

  /// Returns only the models that have already been downloaded to the server.
  Future<List<ApiModelInfo>> installed() async {
    final everything = await _fetch(showAll: true);
    return everything.where((m) => m.downloaded == true).toList();
  }

  Future<List<ApiModelInfo>> _fetch({required bool showAll}) async {
    final uri = _client.apiUriFor(
      '/models',
      query: showAll ? {'show_all': 'true'} : null,
    );
    final body = await _client.getJson(uri);
    final raw = body['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ApiModelInfo.fromJson)
        .toList();
  }
}
