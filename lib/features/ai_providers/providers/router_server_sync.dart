// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/inference/routed_server.dart';
import '../../../infrastructure/nexus/providers/nexus_account_providers.dart';

/// How often we re-pull the account's entitlements (max agents / concurrency)
/// so a plan change made elsewhere reflects in the app without a restart.
const Duration kRouterEntitlementPollInterval = Duration(seconds: 60);

/// Reconciles the built-in Nexus Router (subscription) inference server against
/// the signed-in account: when signed in, a `routed` server row is materialized
/// for the current client with the account token as its API key and its max
/// agents / concurrency pulled from the current subscription; when signed out,
/// it is removed. The InferenceServers stream (Drift `.watch`) picks up the
/// change automatically, so the AI Providers list and every agent's server
/// resolution see the Router appear/disappear with no manual invalidation.
///
/// Re-runs every [kRouterEntitlementPollInterval] (and whenever auth, the
/// current client, or the gateway URL changes) so an upgraded/downgraded plan
/// pulls through. The upsert is change-aware, so an unchanged poll writes
/// nothing and never churns downstream streams.
///
/// Watch this once at the app root (MainShell) to keep it alive for the session.
final routerServerSyncProvider = FutureProvider<void>((ref) async {
  final auth = ref.watch(nexusAuthProvider);
  final clientId = ref.watch(currentClientIdProvider);
  final baseUrl = ref.watch(nexusGatewayBaseUrlProvider);
  final db = ref.read(nexusDatabaseProvider);

  // Wait for the keychain hydrate to settle before touching the DB — otherwise
  // we'd briefly delete the row on every cold start before the token loads.
  if (auth.busy) return;

  final token = auth.token;
  if (!(auth.isSignedIn && token != null && token.isNotEmpty)) {
    await db.removeRoutedServersForClient(clientId);
    return;
  }

  // Pull current entitlements from the account. Tolerate transient failures —
  // a null leaves the stored limits untouched rather than clobbering them.
  int? maxAgents;
  int? maxConcurrency;
  try {
    final client = ref.read(nexusAuthProvider.notifier).authedClient();
    final account = await client.fetchAccount();
    final agents = account.subscription.agentLimit;
    if (agents > 0) maxAgents = agents;
    try {
      final usage = await client.fetchUsage();
      final conc = usage.maxConcurrentConnections;
      if (conc > 0) maxConcurrency = conc;
    } catch (_) {}
  } catch (_) {}

  await db.upsertRoutedServer(
    clientPk: clientId,
    name: kRouterServerName,
    baseUrl: baseUrl,
    apiKey: token,
    maxAgents: maxAgents,
    maxConcurrency: maxConcurrency,
  );

  // Schedule the next poll. A one-shot timer that invalidates self forms the
  // polling loop; it is cancelled if the provider is disposed/recomputed first.
  final timer = Timer(kRouterEntitlementPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
});
