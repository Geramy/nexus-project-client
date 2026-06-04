// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Factory that, given an InferenceServer row, returns the correct implementation
/// of InferenceBackend.
///
/// This is the central place where we decide "for this server, use the Lemonade
/// rich client", "for this server, use the Grok implementation", etc.

import '../models/ui/inference_server.dart' as ui_model;
import 'inference_backend.dart';
// Import the concrete implementation — Dart handles circular imports at runtime.
import '../lemonade/lemonade_backend.dart' show LemonadeBackend;

/// Returns a concrete InferenceBackend for the given server row.
///
/// [agentName] is forwarded as the `X-Nexus-Agent` header so the Router can
/// attribute per-agent cost; pass it when the call is made on behalf of a
/// specific agent persona.
InferenceBackend backendForServer(
  ui_model.InferenceServer server, {
  String? agentName,
}) {
  final type = server.providerType.toLowerCase();

  switch (type) {
    case 'lemonade':
      return LemonadeBackend(server, agentName: agentName);

    // The Nexus Router subscription gateway is OpenAI-compatible and is reached
    // through the same transport (ServerConfig maps api.nexus-projects.ai to
    // /api/v1, which the Router proxy serves).
    case 'routed':
      return LemonadeBackend(server, agentName: agentName);

    default:
      throw UnimplementedError(
        'No backend implementation yet for providerType="$type". '
        'Server: ${server.name}. Implement the backend and wire it here.',
      );
  }
}
