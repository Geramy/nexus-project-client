// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Per-server HTTP client for the admin console.
/// Ported from ~/IdeaProjects/lemonade_mobile/lib/providers/lemonade_client_provider.dart
/// This mirrors the existing lemonadeClientProvider but is scoped specifically
/// to the admin console widgets, making it clear that these tabs depend on a
/// selected server's rich HTTP client.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/infrastructure/lemonade/api/lemonade_client.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/providers/lemonade_servers_provider.dart';

/// Creates one [LemonadeApiClient] per selected server, auto-disposed on change.
final adminConsoleClientProvider = Provider<LemonadeApiClient?>((ref) {
  final server = ref.watch(selectedLemonadeServerProvider);
  if (server == null) return null;
  final client = LemonadeApiClient(server);
  ref.onDispose(client.close);
  return client;
});
