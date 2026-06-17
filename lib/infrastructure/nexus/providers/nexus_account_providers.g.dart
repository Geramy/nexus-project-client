// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nexus_account_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The gateway base URL (overridable). Defaults to the production gateway, but
/// hydrates from secure storage if the user has set an override.
// keepAlive: this hydrates from storage asynchronously after build; if it could
// auto-dispose mid-hydrate, riverpod 3 would strand it (the post-await state set
// is skipped), leaving the gateway URL/auth unhydrated — and the routed server
// never materializes.

@ProviderFor(NexusGatewayBaseUrl)
final nexusGatewayBaseUrlProvider = NexusGatewayBaseUrlProvider._();

/// The gateway base URL (overridable). Defaults to the production gateway, but
/// hydrates from secure storage if the user has set an override.
// keepAlive: this hydrates from storage asynchronously after build; if it could
// auto-dispose mid-hydrate, riverpod 3 would strand it (the post-await state set
// is skipped), leaving the gateway URL/auth unhydrated — and the routed server
// never materializes.
final class NexusGatewayBaseUrlProvider
    extends $NotifierProvider<NexusGatewayBaseUrl, String> {
  /// The gateway base URL (overridable). Defaults to the production gateway, but
  /// hydrates from secure storage if the user has set an override.
  // keepAlive: this hydrates from storage asynchronously after build; if it could
  // auto-dispose mid-hydrate, riverpod 3 would strand it (the post-await state set
  // is skipped), leaving the gateway URL/auth unhydrated — and the routed server
  // never materializes.
  NexusGatewayBaseUrlProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nexusGatewayBaseUrlProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nexusGatewayBaseUrlHash();

  @$internal
  @override
  NexusGatewayBaseUrl create() => NexusGatewayBaseUrl();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$nexusGatewayBaseUrlHash() =>
    r'a209d5425b219aa9298955f25248078d8e5218dd';

/// The gateway base URL (overridable). Defaults to the production gateway, but
/// hydrates from secure storage if the user has set an override.
// keepAlive: this hydrates from storage asynchronously after build; if it could
// auto-dispose mid-hydrate, riverpod 3 would strand it (the post-await state set
// is skipped), leaving the gateway URL/auth unhydrated — and the routed server
// never materializes.

abstract class _$NexusGatewayBaseUrl extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
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

@ProviderFor(nexusAccountClient)
final nexusAccountClientProvider = NexusAccountClientProvider._();

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

final class NexusAccountClientProvider
    extends
        $FunctionalProvider<
          NexusAccountClient,
          NexusAccountClient,
          NexusAccountClient
        >
    with $Provider<NexusAccountClient> {
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
  NexusAccountClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nexusAccountClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nexusAccountClientHash();

  @$internal
  @override
  $ProviderElement<NexusAccountClient> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NexusAccountClient create(Ref ref) {
    return nexusAccountClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NexusAccountClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NexusAccountClient>(value),
    );
  }
}

String _$nexusAccountClientHash() =>
    r'c8d3e7b713f7768cbb09d9961fca26205c9c326e';

/// Signed-in account state. Hydrates the token + cached identity from secure
/// storage on build, then exposes login / register / logout.
// keepAlive: auth must persist for the whole app session AND must not auto-dispose
// while `_hydrate()` awaits the keychain — otherwise the post-await state set is
// skipped (riverpod 3), auth stays stuck `busy: true`, and routerServerSyncProvider
// (which bails on `auth.busy`) never creates the routed inference server.

@ProviderFor(NexusAuth)
final nexusAuthProvider = NexusAuthProvider._();

/// Signed-in account state. Hydrates the token + cached identity from secure
/// storage on build, then exposes login / register / logout.
// keepAlive: auth must persist for the whole app session AND must not auto-dispose
// while `_hydrate()` awaits the keychain — otherwise the post-await state set is
// skipped (riverpod 3), auth stays stuck `busy: true`, and routerServerSyncProvider
// (which bails on `auth.busy`) never creates the routed inference server.
final class NexusAuthProvider
    extends $NotifierProvider<NexusAuth, NexusAuthState> {
  /// Signed-in account state. Hydrates the token + cached identity from secure
  /// storage on build, then exposes login / register / logout.
  // keepAlive: auth must persist for the whole app session AND must not auto-dispose
  // while `_hydrate()` awaits the keychain — otherwise the post-await state set is
  // skipped (riverpod 3), auth stays stuck `busy: true`, and routerServerSyncProvider
  // (which bails on `auth.busy`) never creates the routed inference server.
  NexusAuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nexusAuthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nexusAuthHash();

  @$internal
  @override
  NexusAuth create() => NexusAuth();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NexusAuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NexusAuthState>(value),
    );
  }
}

String _$nexusAuthHash() => r'4a39b99cc16c166cd965f7f00ceff70245e4e4b1';

/// Signed-in account state. Hydrates the token + cached identity from secure
/// storage on build, then exposes login / register / logout.
// keepAlive: auth must persist for the whole app session AND must not auto-dispose
// while `_hydrate()` awaits the keychain — otherwise the post-await state set is
// skipped (riverpod 3), auth stays stuck `busy: true`, and routerServerSyncProvider
// (which bails on `auth.busy`) never creates the routed inference server.

abstract class _$NexusAuth extends $Notifier<NexusAuthState> {
  NexusAuthState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<NexusAuthState, NexusAuthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NexusAuthState, NexusAuthState>,
              NexusAuthState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The public plans + add-ons catalog (no auth required).

@ProviderFor(nexusPlans)
final nexusPlansProvider = NexusPlansProvider._();

/// The public plans + add-ons catalog (no auth required).

final class NexusPlansProvider
    extends
        $FunctionalProvider<
          AsyncValue<PlanCatalog>,
          PlanCatalog,
          FutureOr<PlanCatalog>
        >
    with $FutureModifier<PlanCatalog>, $FutureProvider<PlanCatalog> {
  /// The public plans + add-ons catalog (no auth required).
  NexusPlansProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nexusPlansProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nexusPlansHash();

  @$internal
  @override
  $FutureProviderElement<PlanCatalog> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PlanCatalog> create(Ref ref) {
    return nexusPlans(ref);
  }
}

String _$nexusPlansHash() => r'5999e6c86f2366df305d7454a241bf1807adf417';

/// Current-period usage vs. entitlements (requires sign-in).

@ProviderFor(nexusUsage)
final nexusUsageProvider = NexusUsageProvider._();

/// Current-period usage vs. entitlements (requires sign-in).

final class NexusUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<UsageSnapshot>,
          UsageSnapshot,
          FutureOr<UsageSnapshot>
        >
    with $FutureModifier<UsageSnapshot>, $FutureProvider<UsageSnapshot> {
  /// Current-period usage vs. entitlements (requires sign-in).
  NexusUsageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nexusUsageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nexusUsageHash();

  @$internal
  @override
  $FutureProviderElement<UsageSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<UsageSnapshot> create(Ref ref) {
    return nexusUsage(ref);
  }
}

String _$nexusUsageHash() => r'0cb4f4a3c1d852f4448d68caccab1f64508ed9d7';

/// The signed-in user's account + subscription summary.

@ProviderFor(nexusAccountSummary)
final nexusAccountSummaryProvider = NexusAccountSummaryProvider._();

/// The signed-in user's account + subscription summary.

final class NexusAccountSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<AccountSummary>,
          AccountSummary,
          FutureOr<AccountSummary>
        >
    with $FutureModifier<AccountSummary>, $FutureProvider<AccountSummary> {
  /// The signed-in user's account + subscription summary.
  NexusAccountSummaryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nexusAccountSummaryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nexusAccountSummaryHash();

  @$internal
  @override
  $FutureProviderElement<AccountSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AccountSummary> create(Ref ref) {
    return nexusAccountSummary(ref);
  }
}

String _$nexusAccountSummaryHash() =>
    r'716ee3dd3a4756945f500e61ca5e6a589e31ac0b';

/// Per-agent cost breakdown over [days] (null = current billing period).

@ProviderFor(nexusAgentUsage)
final nexusAgentUsageProvider = NexusAgentUsageFamily._();

/// Per-agent cost breakdown over [days] (null = current billing period).

final class NexusAgentUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentUsageReport>,
          AgentUsageReport,
          FutureOr<AgentUsageReport>
        >
    with $FutureModifier<AgentUsageReport>, $FutureProvider<AgentUsageReport> {
  /// Per-agent cost breakdown over [days] (null = current billing period).
  NexusAgentUsageProvider._({
    required NexusAgentUsageFamily super.from,
    required int? super.argument,
  }) : super(
         retry: null,
         name: r'nexusAgentUsageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$nexusAgentUsageHash();

  @override
  String toString() {
    return r'nexusAgentUsageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentUsageReport> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentUsageReport> create(Ref ref) {
    final argument = this.argument as int?;
    return nexusAgentUsage(ref, days: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is NexusAgentUsageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$nexusAgentUsageHash() => r'2bb1c4f99cf4b0102dd53b5fd7f76ddd54250ba8';

/// Per-agent cost breakdown over [days] (null = current billing period).

final class NexusAgentUsageFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentUsageReport>, int?> {
  NexusAgentUsageFamily._()
    : super(
        retry: null,
        name: r'nexusAgentUsageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-agent cost breakdown over [days] (null = current billing period).

  NexusAgentUsageProvider call({int? days}) =>
      NexusAgentUsageProvider._(argument: days, from: this);

  @override
  String toString() => r'nexusAgentUsageProvider';
}
