// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Factory that, given an InferenceServer row, returns the correct implementation
/// of InferenceBackend.
///
/// This is the central place where we decide "for this server, use the Lemonade
/// rich client", "for this server, use the Grok implementation", etc.

import 'dart:io' show HttpClient;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

import '../models/ui/inference_server.dart' as ui_model;
import 'inference_backend.dart';
// Import the concrete implementation — Dart handles circular imports at runtime.
import '../lemonade/lemonade_backend.dart' show LemonadeBackend;

/// One shared HTTP transport per HOST, reused by every backend that talks to it.
///
/// Backends used to each create their own `http.Client`, and most callers (the
/// coordinator chat, the orchestrator stages, task-gen, setup) never closed
/// them — so every re-init leaked a keep-alive socket that the Nexus Router kept
/// counting against the plan's concurrent-connection cap, eventually 429-ing
/// even with no agents running. Pooling per host means idle sockets are REUSED
/// (and released after a short idle timeout) instead of multiplying.
final Map<String, http.Client> _sharedClients = {};

http.Client _sharedClientFor(ui_model.InferenceServer server) {
  final uri = Uri.tryParse(server.baseUrl);
  final key = uri == null
      ? server.baseUrl
      : '${uri.scheme}://${uri.host}:${uri.port}';
  return _sharedClients.putIfAbsent(key, () {
    final io = HttpClient()
      // Release idle keep-alive sockets so they stop counting toward the router's
      // connection cap once nothing is in flight — but NOT so aggressively that a
      // streaming response with a normal gap is killed. `idleTimeout` is the max
      // time a connection may have NO data flowing, including while waiting for a
      // model's first token; at 5s a loaded 35B model's time-to-first-token (or an
      // inter-token gap) tripped it → "Connection closed while receiving data",
      // which broke whole turns. 30s clears the realistic streaming gaps; a truly
      // dead stream is still caught by the orchestrator's 4-min turn watchdog, and
      // project switches force-close via resetInferenceConnections().
      ..idleTimeout = const Duration(seconds: 30);
    return IOClient(io);
  });
}

/// Immediately free ALL inference connections: closing the shared clients aborts
/// every in-flight request (a worker mid-turn, a streaming chat) and drops their
/// sockets, so the router's concurrent-connection count returns to zero at once.
/// The next request lazily creates a fresh pooled client. Used when leaving a
/// project so the next one gets the full connection budget immediately (pausing/
/// stopping the orchestrator alone leaves an in-flight turn holding its socket).
void resetInferenceConnections() {
  final clients = _sharedClients.values.toList();
  _sharedClients.clear();
  for (final c in clients) {
    c.close();
  }
}

/// Returns a concrete InferenceBackend for the given server row.
///
/// [agentName] is forwarded as the `X-Nexus-Agent` header so the Router can
/// attribute per-agent cost; pass it when the call is made on behalf of a
/// specific agent persona.
///
/// [sessionId] is forwarded as the `X-Nexus-Session` header — a stable id for the
/// message session (conversation / agent run). The Router pins a session to one
/// warm backend and balances different sessions across the fleet, so a single
/// conversation stays warm while concurrent agents fan out across servers.
InferenceBackend backendForServer(
  ui_model.InferenceServer server, {
  String? agentName,
  String? sessionId,
}) {
  final type = server.providerType.toLowerCase();

  switch (type) {
    case 'lemonade':
      return LemonadeBackend(
        server,
        agentName: agentName,
        sessionId: sessionId,
        client: _sharedClientFor(server),
      );

    // The Nexus Router subscription gateway is OpenAI-compatible and is reached
    // through the same transport (ServerConfig maps api.nexus-projects.ai to
    // /api/v1, which the Router proxy serves).
    case 'routed':
      return LemonadeBackend(
        server,
        agentName: agentName,
        sessionId: sessionId,
        client: _sharedClientFor(server),
      );

    default:
      throw UnimplementedError(
        'No backend implementation yet for providerType="$type". '
        'Server: ${server.name}. Implement the backend and wire it here.',
      );
  }
}
