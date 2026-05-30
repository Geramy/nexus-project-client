// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Riverpod providers for the Nexus Account feature, using the @riverpod
/// codegen pattern (see core/providers/app_shell_provider.dart).
///
///   - [NexusGatewayBaseUrl]  — configurable gateway base (hydrated from store).
///   - [nexusAccountClient]   — a NexusAccountClient bound to the current token.
///   - [NexusAuth]            — signed-in state (token + user + client) with
///                              login / register / logout; hydrates on build.
///   - [nexusPlans]           — Future catalog of plans + add-ons (no auth).
///   - [nexusUsage]           — Future current-period usage (auth).
///   - [nexusAccountSummary]  — Future account + subscription (auth).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/nexus_account_models.dart';
import '../nexus_account_client.dart';
import '../nexus_account_store.dart';

part 'nexus_account_providers.g.dart';

/// Immutable signed-in auth state held by [NexusAuth].
class NexusAuthState {
  final String? token;
  final NexusUser? user;
  final NexusClient? client;

  /// True while the initial hydrate / a login/register call is in flight.
  final bool busy;

  const NexusAuthState({
    this.token,
    this.user,
    this.client,
    this.busy = false,
  });

  bool get isSignedIn => token != null && token!.isNotEmpty;

  NexusAuthState copyWith({
    String? token,
    NexusUser? user,
    NexusClient? client,
    bool? busy,
  }) {
    return NexusAuthState(
      token: token ?? this.token,
      user: user ?? this.user,
      client: client ?? this.client,
      busy: busy ?? this.busy,
    );
  }

  static const signedOut = NexusAuthState();
}

/// The gateway base URL (overridable). Defaults to the production gateway, but
/// hydrates from secure storage if the user has set an override.
@riverpod
class NexusGatewayBaseUrl extends _$NexusGatewayBaseUrl {
  @override
  String build() {
    // Kick off async hydration; default is returned synchronously.
    NexusAccountStore.readGatewayBaseUrl().then((saved) {
      if (saved != null && saved.isNotEmpty && saved != state) {
        state = saved;
      }
    });
    return NexusAccountClient.defaultGatewayBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    state = url;
    await NexusAccountStore.writeGatewayBaseUrl(url);
  }
}

/// A base (unauthenticated) [NexusAccountClient] bound to the current gateway
/// base URL. Rebuilds whenever the base URL changes.
///
/// This provider deliberately does NOT watch [nexusAuthProvider]: doing so would
/// create a dependency cycle, because [NexusAuth] reads this client to make its
/// login/register/usage calls. Authenticated callers obtain a token-bound client
/// via [NexusAuth.authedClient] (which uses [NexusAccountClient.withToken]).
///
/// Kept alive so the shared http.Client socket pool is never disposed out from
/// under an in-flight request. [NexusAuth] reaches it via a one-shot `ref.read`
/// (to avoid a dependency cycle), which would otherwise let an auto-dispose
/// provider close the socket mid-call and surface "Connection attempt cancelled".
@Riverpod(keepAlive: true)
NexusAccountClient nexusAccountClient(Ref ref) {
  final baseUrl = ref.watch(nexusGatewayBaseUrlProvider);
  final client = NexusAccountClient(baseUrl: baseUrl);
  ref.onDispose(client.close);
  return client;
}

/// Signed-in account state. Hydrates the token + cached identity from secure
/// storage on build, then exposes login / register / logout.
@riverpod
class NexusAuth extends _$NexusAuth {
  @override
  NexusAuthState build() {
    _hydrate();
    // Start in a "hydrating" state (busy, not yet signed in) so the Account UI
    // can show a spinner instead of flashing the login form before the saved
    // token is read back from secure storage.
    return const NexusAuthState(busy: true);
  }

  Future<void> _hydrate() async {
    final token = await NexusAccountStore.readToken();
    if (token == null || token.isEmpty) {
      state = NexusAuthState.signedOut;
      return;
    }
    final identity = await NexusAccountStore.readIdentity();
    state = NexusAuthState(
      token: token,
      user: identity?.user,
      client: identity?.client,
    );
  }

  /// Returns the base client bound to the current token (or unauthenticated when
  /// signed out). Uses [ref.read] (one-shot) so this Notifier never *watches*
  /// the client provider — keeping the dependency edge one-directional and
  /// avoiding a circular dependency.
  NexusAccountClient authedClient() =>
      ref.read(nexusAccountClientProvider).withToken(state.token);

  NexusAccountClient _client() => authedClient();

  /// Sign in with email/password. Throws on failure (caller surfaces the
  /// server's message); state is updated on success.
  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(busy: true);
    try {
      final result = await _client().login(email: email, password: password);
      await _persist(result);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Register a new tenant. Throws on validation failure (caller surfaces the
  /// server's 400 message); state is updated on success.
  Future<void> register({
    required String clientName,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(busy: true);
    try {
      final result = await _client().register(
        clientName: clientName,
        email: email,
        password: password,
      );
      await _persist(result);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> _persist(AuthResult result) async {
    await NexusAccountStore.writeToken(result.token);
    await NexusAccountStore.writeIdentity(result.user, result.client);
    // Replace state outright (token is non-null now) so isSignedIn flips true.
    state = NexusAuthState(
      token: result.token,
      user: result.user,
      client: result.client,
      busy: state.busy,
    );
  }

  /// Sign out: clear the keychain and reset to signed-out.
  Future<void> logout() async {
    await NexusAccountStore.clear();
    state = NexusAuthState.signedOut;
  }
}

/// The public plans + add-ons catalog (no auth required).
@Riverpod(keepAlive: true)
Future<PlanCatalog> nexusPlans(Ref ref) {
  final client = ref.watch(nexusAccountClientProvider);
  return client.fetchPlans();
}

/// Current-period usage vs. entitlements (requires sign-in).
@riverpod
Future<UsageSnapshot> nexusUsage(Ref ref) {
  // Re-fetch when the token changes (login/logout)…
  ref.watch(nexusAuthProvider.select((s) => s.token));
  // …and rebuild when the gateway base URL changes.
  ref.watch(nexusGatewayBaseUrlProvider);
  final client = ref.read(nexusAuthProvider.notifier).authedClient();
  return client.fetchUsage();
}

/// The signed-in user's account + subscription summary.
@riverpod
Future<AccountSummary> nexusAccountSummary(Ref ref) {
  ref.watch(nexusAuthProvider.select((s) => s.token));
  ref.watch(nexusGatewayBaseUrlProvider);
  final client = ref.read(nexusAuthProvider.notifier).authedClient();
  return client.fetchAccount();
}
