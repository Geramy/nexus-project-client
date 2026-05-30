// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../build_backend.dart';
import '../build_models.dart';

/// A [BuildBackend] that delegates execution to a remote "Nexus build server"
/// over HTTP, using only `dart:io`'s [HttpClient] and `dart:convert` (no extra
/// dependencies).
///
/// ## Protocol (the app's own contract with a Nexus build server)
///
/// This is NOT a standard API — it is a small protocol defined by this client
/// and expected to be implemented by the paired build server:
///
///   * `GET  <baseUrl>/health` — returns 200 when the server is ready.
///   * `POST <baseUrl>/runs`   — body is the JSON-serialized [CiRunRequest]
///     (see [_requestToJson]). The response is an **NDJSON** stream: one JSON
///     object per line. Each line is one of:
///       - `{"type":"log","jobIndex":..,"stepIndex":..,"stream":"stdout|stderr|system","line":".."}`
///       - `{"type":"result","status":"..","jobs":[{"name":..,"status":..,
///          "steps":[{"name":..,"status":..,"exitCode":..}]}],"error":null}`
///     The `result` line is terminal and ends the stream.
///
/// When [authToken] is set it is sent as `Authorization: Bearer <token>` on
/// every request.
class RemoteBuildBackend implements BuildBackend {
  /// Normalized base URL (no trailing slash).
  final String baseUrl;
  final String? authToken;
  final HttpClient _httpClient;

  RemoteBuildBackend({
    required String baseUrl,
    this.authToken,
    HttpClient? httpClient,
  })  : baseUrl = _normalize(baseUrl),
        _httpClient = httpClient ?? HttpClient();

  static String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  @override
  CiBackendKind get kind => CiBackendKind.remote;

  void _applyAuth(HttpClientRequest req) {
    final token = authToken;
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
  }

  @override
  Future<String?> unavailableReason() async {
    try {
      final req = await _httpClient.getUrl(Uri.parse('$baseUrl/health'));
      _applyAuth(req);
      final resp = await req.close();
      await resp.drain<void>();
      if (resp.statusCode == 200) return null;
      return 'Nexus build server at $baseUrl is unhealthy '
          '(HTTP ${resp.statusCode}).';
    } on SocketException catch (e) {
      return 'Nexus build server at $baseUrl is unreachable: ${e.message}';
    } catch (e) {
      return 'Nexus build server at $baseUrl is unreachable: $e';
    }
  }

  Map<String, dynamic> _requestToJson(CiRunRequest request) => {
        'kind': request.kind.wire,
        'dockerfilePath': request.dockerfilePath,
        'imageTag': request.imageTag,
        'buildContext': request.buildContext,
        'buildArgs': request.buildArgs,
        'workflowPath': request.workflowPath,
        'branch': request.branch,
        'commitOid': request.commitOid,
      };

  @override
  Future<CiRunOutcome> execute(
    CiRunRequest request, {
    required CiLogSink log,
    CiCancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      return const CiRunOutcome(status: CiStatus.cancelled);
    }

    HttpClientRequest? clientRequest;
    var cancelled = false;
    StreamSubscription<void>? cancelSub;

    void abort() {
      cancelled = true;
      clientRequest?.abort();
    }

    if (cancel != null) {
      cancelSub = cancel.whenCancelled.asStream().listen((_) => abort());
    }

    try {
      final req = await _httpClient.postUrl(Uri.parse('$baseUrl/runs'));
      clientRequest = req;
      _applyAuth(req);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(_requestToJson(request)));

      // If cancellation arrived while we were setting up, honor it now.
      if (cancel?.isCancelled ?? false) {
        abort();
      }

      final resp = await req.close();

      if (resp.statusCode != 200) {
        await resp.drain<void>();
        log(CiLogEvent(
          'Nexus build server returned HTTP ${resp.statusCode}.',
          stream: CiLogStream.system,
        ));
        return CiRunOutcome.failedToStart(
          'Nexus build server returned HTTP ${resp.statusCode}.',
        );
      }

      CiRunOutcome? outcome;
      final lines = resp
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;

        final Map<String, dynamic> obj;
        try {
          obj = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          // Skip malformed lines rather than aborting the whole run.
          continue;
        }

        final type = obj['type'] as String?;
        if (type == 'log') {
          log(CiLogEvent(
            (obj['line'] as String?) ?? '',
            jobIndex: (obj['jobIndex'] as num?)?.toInt(),
            stepIndex: (obj['stepIndex'] as num?)?.toInt(),
            stream: CiLogStreamX.fromWire(obj['stream'] as String?),
          ));
        } else if (type == 'result') {
          outcome = _parseResult(obj);
        }
      }

      if (cancelled) {
        return const CiRunOutcome(status: CiStatus.cancelled);
      }

      return outcome ??
          CiRunOutcome.failedToStart(
            'Nexus build server stream ended without a result.',
          );
    } on HttpException catch (e) {
      if (cancelled) {
        return const CiRunOutcome(status: CiStatus.cancelled);
      }
      log(CiLogEvent('Remote build failed: $e', stream: CiLogStream.system));
      return CiRunOutcome.failedToStart('Remote build failed: $e');
    } on SocketException catch (e) {
      if (cancelled) {
        return const CiRunOutcome(status: CiStatus.cancelled);
      }
      log(CiLogEvent('Remote build failed: ${e.message}',
          stream: CiLogStream.system));
      return CiRunOutcome.failedToStart('Remote build failed: ${e.message}');
    } catch (e) {
      if (cancelled) {
        return const CiRunOutcome(status: CiStatus.cancelled);
      }
      log(CiLogEvent('Remote build failed: $e', stream: CiLogStream.system));
      return CiRunOutcome.failedToStart('Remote build failed: $e');
    } finally {
      await cancelSub?.cancel();
    }
  }

  CiRunOutcome _parseResult(Map<String, dynamic> obj) {
    final jobsRaw = (obj['jobs'] as List?) ?? const [];
    final jobs = jobsRaw
        .whereType<Map>()
        .map((j) => _parseJob(j.cast<String, dynamic>()))
        .toList();
    return CiRunOutcome(
      status: CiStatusX.fromWire(obj['status'] as String?),
      jobs: jobs,
      error: obj['error'] as String?,
    );
  }

  CiJobOutcome _parseJob(Map<String, dynamic> obj) {
    final stepsRaw = (obj['steps'] as List?) ?? const [];
    final steps = stepsRaw
        .whereType<Map>()
        .map((s) => _parseStep(s.cast<String, dynamic>()))
        .toList();
    return CiJobOutcome(
      name: (obj['name'] as String?) ?? '',
      status: CiStatusX.fromWire(obj['status'] as String?),
      steps: steps,
    );
  }

  CiStepOutcome _parseStep(Map<String, dynamic> obj) => CiStepOutcome(
        name: (obj['name'] as String?) ?? '',
        status: CiStatusX.fromWire(obj['status'] as String?),
        exitCode: (obj['exitCode'] as num?)?.toInt(),
      );
}
