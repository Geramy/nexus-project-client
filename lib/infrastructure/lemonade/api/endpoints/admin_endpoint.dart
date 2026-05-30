// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Ported from ~/IdeaProjects/lemonade_mobile/lib/api/endpoints/admin_endpoint.dart
/// Extended with full admin API: load, unload, delete, install, uninstall, stats.
import 'dart:async';
import 'dart:convert';

import '../lemonade_client.dart';
import '../sse/sse_parser.dart';

class AdminEndpoint {
  final LemonadeApiClient _client;
  AdminEndpoint(this._client);

  Future<Map<String, dynamic>> health() {
    return _client.getJson(_client.apiUriFor('/health'));
  }

  Future<bool> live() async {
    try {
      final body = await _client.getJson(_client.rootUriFor('/live'));
      return body['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> systemInfo() {
    return _client.getJson(_client.apiUriFor('/system-info'));
  }

  /// GET /v1/stats — performance stats from the last request.
  Future<Map<String, dynamic>> stats() {
    return _client.getJson(_client.apiUriFor('/stats'));
  }

  /// POST /v1/load — load a model into memory.
  Future<Map<String, dynamic>> load({
    required String modelName,
    int? ctxSize,
    String? llamacppBackend,
    String? llamacppArgs,
  }) {
    final body = <String, dynamic>{'model_name': modelName};
    if (ctxSize != null) body['ctx_size'] = ctxSize;
    if (llamacppBackend != null) body['llamacpp_backend'] = llamacppBackend;
    if (llamacppArgs != null) body['llamacpp_args'] = llamacppArgs;
    return _client.postJson(
      _client.apiUriFor('/load'),
      body,
      timeout: const Duration(minutes: 10),
    );
  }

  /// POST /v1/unload — unload a model (or all if no modelName).
  Future<Map<String, dynamic>> unload({String? modelName}) {
    final body = <String, dynamic>{};
    if (modelName != null) body['model_name'] = modelName;
    return _client.postJson(_client.apiUriFor('/unload'), body);
  }

  /// POST /v1/delete — remove a model from local storage.
  Future<Map<String, dynamic>> delete({required String modelName}) {
    return _client.postJson(
      _client.apiUriFor('/delete'),
      {'model_name': modelName},
    );
  }

  /// POST /v1/install — install or update a recipe/backend pair.
  Future<Map<String, dynamic>> install({
    required String recipe,
    required String backend,
    bool force = false,
  }) {
    return _client.postJson(
      _client.apiUriFor('/install'),
      {
        'recipe': recipe,
        'backend': backend,
        'stream': false,
        if (force) 'force': true,
      },
      timeout: const Duration(minutes: 30),
    );
  }

  /// POST /v1/uninstall — remove a backend.
  Future<Map<String, dynamic>> uninstall({
    required String recipe,
    required String backend,
  }) {
    return _client.postJson(
      _client.apiUriFor('/uninstall'),
      {'recipe': recipe, 'backend': backend},
    );
  }

  /// POST /v1/pull (stream=true) — install with progress events.
  /// This is the key method for "available to download or are downloaded".
  Stream<PullEvent> pullStream({
    required String modelName,
    String? checkpoint,
    String? recipe,
    bool? reasoning,
    bool? vision,
    bool? embedding,
    bool? reranking,
    String? mmproj,
  }) async* {
    final body = _buildPullBody(
      modelName: modelName,
      checkpoint: checkpoint,
      recipe: recipe,
      reasoning: reasoning,
      vision: vision,
      embedding: embedding,
      reranking: reranking,
      mmproj: mmproj,
      stream: true,
    );
    final sse = _client.streamSseFromJsonPost(
      _client.apiUriFor('/pull'),
      body,
    );

    await for (final SseEvent ev in sse) {
      final data = ev.data.trim();
      if (data.isEmpty) continue;
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}
      if (payload == null) continue;

      switch (ev.event) {
        case 'progress':
          yield PullEvent.progress(
            file: payload['file'] as String?,
            fileIndex: (payload['file_index'] as num?)?.toInt(),
            totalFiles: (payload['total_files'] as num?)?.toInt(),
            bytesDownloaded: (payload['bytes_downloaded'] as num?)?.toInt(),
            bytesTotal: (payload['bytes_total'] as num?)?.toInt(),
            percent: (payload['percent'] as num?)?.toDouble(),
          );
          break;
        case 'complete':
          yield PullEvent.complete(
            fileIndex: (payload['file_index'] as num?)?.toInt(),
            totalFiles: (payload['total_files'] as num?)?.toInt(),
          );
          return;
        case 'error':
          yield PullEvent.error(payload['error']?.toString() ?? 'Unknown error');
          return;
        default:
          break;
      }
    }
  }

  Map<String, dynamic> _buildPullBody({
    required String modelName,
    String? checkpoint,
    String? recipe,
    bool? reasoning,
    bool? vision,
    bool? embedding,
    bool? reranking,
    String? mmproj,
    required bool stream,
  }) {
    final body = <String, dynamic>{'model_name': modelName, 'stream': stream};
    if (checkpoint != null) body['checkpoint'] = checkpoint;
    if (recipe != null) body['recipe'] = recipe;
    if (reasoning != null) body['reasoning'] = reasoning;
    if (vision != null) body['vision'] = vision;
    if (embedding != null) body['embedding'] = embedding;
    if (reranking != null) body['reranking'] = reranking;
    if (mmproj != null) body['mmproj'] = mmproj;
    return body;
  }
}

/// Streaming events from `POST /v1/pull` with `stream: true`.
sealed class PullEvent {
  const PullEvent();

  factory PullEvent.progress({
    String? file,
    int? fileIndex,
    int? totalFiles,
    int? bytesDownloaded,
    int? bytesTotal,
    double? percent,
  }) = PullProgress;

  factory PullEvent.complete({int? fileIndex, int? totalFiles}) = PullComplete;
  factory PullEvent.error(String message) = PullError;
}

class PullProgress extends PullEvent {
  final String? file;
  final int? fileIndex;
  final int? totalFiles;
  final int? bytesDownloaded;
  final int? bytesTotal;
  final double? percent;

  const PullProgress({
    this.file,
    this.fileIndex,
    this.totalFiles,
    this.bytesDownloaded,
    this.bytesTotal,
    this.percent,
  });
}

class PullComplete extends PullEvent {
  final int? fileIndex;
  final int? totalFiles;
  const PullComplete({this.fileIndex, this.totalFiles});
}

class PullError extends PullEvent {
  final String message;
  const PullError(this.message);
}
