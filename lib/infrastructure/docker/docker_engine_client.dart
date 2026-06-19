// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'docker_models.dart';
import 'docker_named_pipe.dart';

/// Thrown when the Docker daemon can't be reached or returns an error status.
class DockerEngineException implements Exception {
  final String message;
  DockerEngineException(this.message);
  @override
  String toString() => 'DockerEngineException: $message';
}

/// A thin client for the Docker Engine REST API.
///
/// Three transports (the app is not sandboxed, so it reaches the daemon's
/// native endpoint directly — no TCP bridge):
///   - `unix:///path/to/docker.sock` — Unix socket (macOS/Linux: OrbStack,
///     Docker Desktop). Routed via [HttpClient.connectionFactory].
///   - `npipe:////./pipe/docker_engine` — Windows named pipe (Docker Desktop),
///     bridged in-process by [WindowsDockerPipe] (Win32 FFI).
///   - `http://host:port` — plain TCP, when the daemon exposes a TCP port.
class DockerEngineClient {
  /// The endpoint as configured, e.g. `unix:///Users/me/.orbstack/run/docker.sock`
  /// or `http://localhost:2375`. Kept verbatim for display/diagnostics.
  final String endpoint;

  /// Base used to form request URIs. For a Unix socket the host is irrelevant
  /// (the connection factory routes to the socket), so a placeholder is used.
  final String _httpBase;
  final HttpClient _http;

  DockerEngineClient({
    String baseUrl = 'http://localhost:2375',
    HttpClient? httpClient,
  }) : endpoint = baseUrl,
       _httpBase = _resolveHttpBase(baseUrl),
       _http = httpClient ?? _buildClient(baseUrl);

  static String _resolveHttpBase(String baseUrl) {
    if (baseUrl.startsWith('unix://') || baseUrl.startsWith('npipe://')) {
      return 'http://localhost';
    }
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  static HttpClient _buildClient(String baseUrl) {
    final client = HttpClient();
    if (baseUrl.startsWith('unix://')) {
      final socketPath = baseUrl.substring('unix://'.length);
      client.connectionFactory = (uri, proxyHost, proxyPort) {
        final addr = InternetAddress(
          socketPath,
          type: InternetAddressType.unix,
        );
        return Socket.startConnect(addr, 0);
      };
    } else if (baseUrl.startsWith('npipe://')) {
      // npipe:////./pipe/docker_engine -> \\.\pipe\docker_engine
      final pipePath = baseUrl
          .substring('npipe://'.length)
          .replaceAll('/', r'\');
      final pipe = WindowsDockerPipe.forPath(pipePath);
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        final port = await pipe.port;
        return Socket.startConnect(InternetAddress.loopbackIPv4, port);
      };
    }
    return client;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$_httpBase$path');
    return query == null
        ? u
        : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// Returns null if the daemon is reachable, otherwise a human-readable reason.
  Future<String?> unavailableReason() async {
    try {
      await version();
      return null;
    } on DockerEngineException catch (e) {
      return e.message;
    } catch (e) {
      return 'Cannot reach Docker at $endpoint: $e. '
          'Is the daemon running and reachable at this endpoint?';
    }
  }

  Future<DockerVersion> version() async {
    final json = await _getJson('/version');
    if (json is! Map<String, dynamic>) {
      throw DockerEngineException('Unexpected /version response.');
    }
    return DockerVersion.fromJson(json);
  }

  Future<List<DockerImage>> listImages() async {
    final json = await _getJson('/images/json');
    if (json is! List)
      throw DockerEngineException('Unexpected /images/json response.');
    return json
        .whereType<Map<String, dynamic>>()
        .map(DockerImage.fromJson)
        .toList();
  }

  Future<List<DockerContainer>> listContainers({bool all = true}) async {
    final json = await _getJson('/containers/json', {'all': all ? '1' : '0'});
    if (json is! List)
      throw DockerEngineException('Unexpected /containers/json response.');
    return json
        .whereType<Map<String, dynamic>>()
        .map(DockerContainer.fromJson)
        .toList();
  }

  Future<void> removeImage(String idOrTag, {bool force = false}) async {
    await _delete('/images/${Uri.encodeComponent(idOrTag)}', {
      'force': force ? '1' : '0',
    });
  }

  Future<void> removeContainer(String id, {bool force = true}) async {
    await _delete('/containers/${Uri.encodeComponent(id)}', {
      'force': force ? '1' : '0',
    });
  }

  Future<void> startContainer(String id) async {
    await _postEmpty('/containers/${Uri.encodeComponent(id)}/start');
  }

  Future<void> stopContainer(String id) async {
    await _postEmpty('/containers/${Uri.encodeComponent(id)}/stop');
  }

  /// Create a container from [imageTag] (does NOT start it — call
  /// [startContainer] with the returned id, or use [runContainer]).
  ///
  /// [env] are `KEY=VALUE` strings. [portBindings] maps a container port
  /// (`'8080'` or `'8080/tcp'`) to a host port (`'8080'`).
  Future<String> createContainer({
    required String imageTag,
    String? name,
    List<String> env = const [],
    Map<String, String> portBindings = const {},
  }) async {
    final exposed = <String, dynamic>{};
    final bindings = <String, dynamic>{};
    portBindings.forEach((containerPort, hostPort) {
      final key = containerPort.contains('/')
          ? containerPort
          : '$containerPort/tcp';
      exposed[key] = <String, dynamic>{};
      bindings[key] = [
        {'HostPort': hostPort},
      ];
    });
    final body = <String, dynamic>{
      'Image': imageTag,
      if (env.isNotEmpty) 'Env': env,
      if (exposed.isNotEmpty) 'ExposedPorts': exposed,
      'HostConfig': {if (bindings.isNotEmpty) 'PortBindings': bindings},
    };
    final json = await _postJson(
      '/containers/create',
      body,
      (name != null && name.trim().isNotEmpty) ? {'name': name.trim()} : null,
    );
    if (json is Map && json['Id'] is String) return json['Id'] as String;
    throw DockerEngineException(
      'Unexpected /containers/create response: $json',
    );
  }

  /// Create AND start a container from [imageTag] (the `docker run` equivalent);
  /// returns the new container id.
  Future<String> runContainer({
    required String imageTag,
    String? name,
    List<String> env = const [],
    Map<String, String> portBindings = const {},
  }) async {
    final id = await createContainer(
      imageTag: imageTag,
      name: name,
      env: env,
      portBindings: portBindings,
    );
    await startContainer(id);
    return id;
  }

  /// Build an image from [contextTar] (a tar of the build context, with the
  /// Dockerfile inside it). Streams decoded progress/log lines as the daemon
  /// emits them. The stream completes when the build finishes; a failed build
  /// emits a final error event (it does not throw mid-stream).
  Stream<DockerBuildEvent> buildImage({
    required Uint8List contextTar,
    required String imageTag,
    String dockerfile = 'Dockerfile',
    Map<String, String> buildArgs = const {},
  }) async* {
    final query = <String, String>{
      't': imageTag,
      'dockerfile': dockerfile,
      'rm': '1',
    };
    if (buildArgs.isNotEmpty) {
      query['buildargs'] = jsonEncode(buildArgs);
    }

    final HttpClientResponse resp;
    try {
      final req = await _http.postUrl(_uri('/build', query));
      req.headers.contentType = ContentType('application', 'x-tar');
      req.headers.contentLength = contextTar.length;
      req.add(contextTar);
      resp = await req.close();
    } catch (e) {
      yield DockerBuildEvent(
        'Cannot reach Docker at $endpoint: $e',
        isError: true,
      );
      return;
    }

    if (resp.statusCode >= 400) {
      final body = await resp.transform(utf8.decoder).join();
      yield DockerBuildEvent(
        'Build request failed (${resp.statusCode}): $body',
        isError: true,
      );
      return;
    }

    // The daemon streams newline-delimited JSON objects: {"stream":"..."},
    // {"errorDetail":...,"error":"..."}, {"aux":{"ID":"sha256:..."}}.
    final lines = resp.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      Map<String, dynamic>? obj;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) obj = decoded;
      } catch (_) {
        yield DockerBuildEvent(trimmed);
        continue;
      }
      if (obj == null) continue;

      if (obj['error'] != null) {
        yield DockerBuildEvent('${obj['error']}', isError: true);
      } else if (obj['stream'] != null) {
        final text = '${obj['stream']}';
        final clean = text.endsWith('\n')
            ? text.substring(0, text.length - 1)
            : text;
        if (clean.isNotEmpty) yield DockerBuildEvent(clean);
      } else if (obj['aux'] is Map && (obj['aux'] as Map)['ID'] != null) {
        yield DockerBuildEvent('Built image: ${(obj['aux'] as Map)['ID']}');
      } else if (obj['status'] != null) {
        yield DockerBuildEvent('${obj['status']}');
      }
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    final req = await _http.getUrl(_uri(path, query));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) {
      throw DockerEngineException('GET $path → ${resp.statusCode}: $body');
    }
    return body.isEmpty ? null : jsonDecode(body);
  }

  Future<void> _delete(String path, [Map<String, String>? query]) async {
    final req = await _http.deleteUrl(_uri(path, query));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) {
      throw DockerEngineException('DELETE $path → ${resp.statusCode}: $body');
    }
  }

  Future<dynamic> _postJson(
    String path,
    Object body, [
    Map<String, String>? query,
  ]) async {
    final req = await _http.postUrl(_uri(path, query));
    req.headers.contentType = ContentType('application', 'json');
    final bytes = utf8.encode(jsonEncode(body));
    req.headers.contentLength = bytes.length;
    req.add(bytes);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    if (resp.statusCode >= 400) {
      throw DockerEngineException('POST $path → ${resp.statusCode}: $respBody');
    }
    return respBody.isEmpty ? null : jsonDecode(respBody);
  }

  Future<void> _postEmpty(String path, [Map<String, String>? query]) async {
    final req = await _http.postUrl(_uri(path, query));
    req.headers.contentLength = 0;
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    // 204 = success, 304 = already in desired state (start/stop) — both fine.
    if (resp.statusCode >= 400 && resp.statusCode != 304) {
      throw DockerEngineException('POST $path → ${resp.statusCode}: $body');
    }
  }

  void close() => _http.close(force: true);
}
