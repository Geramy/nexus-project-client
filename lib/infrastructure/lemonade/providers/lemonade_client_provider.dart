// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Ported from ~/IdeaProjects/lemonade_mobile/lib/providers/lemonade_client_provider.dart
/// One [LemonadeApiClient] per active Lemonade server (the rich http/SSE client).
/// Only created for servers that are detected as full local Lemonade instances
/// (those with omni collections or admin endpoints). Routed servers use other
/// InferenceBackend implementations (migration in progress for chat/voice).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lemonade_client.dart';
import 'lemonade_servers_provider.dart';

/// One [LemonadeApiClient] per active server. Auto-disposed on server change.
final lemonadeClientProvider = Provider<LemonadeApiClient?>((ref) {
  final server = ref.watch(selectedLemonadeServerProvider);
  if (server == null) return null;
  final client = LemonadeApiClient(server);
  ref.onDispose(client.close);
  return client;
});
