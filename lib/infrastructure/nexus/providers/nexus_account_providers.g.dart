// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nexus_account_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$nexusAccountClientHash() =>
    r'c8d3e7b713f7768cbb09d9961fca26205c9c326e';

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
///
/// Copied from [nexusAccountClient].
@ProviderFor(nexusAccountClient)
final nexusAccountClientProvider = Provider<NexusAccountClient>.internal(
  nexusAccountClient,
  name: r'nexusAccountClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nexusAccountClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NexusAccountClientRef = ProviderRef<NexusAccountClient>;
String _$nexusPlansHash() => r'5999e6c86f2366df305d7454a241bf1807adf417';

/// The public plans + add-ons catalog (no auth required).
///
/// Copied from [nexusPlans].
@ProviderFor(nexusPlans)
final nexusPlansProvider = FutureProvider<PlanCatalog>.internal(
  nexusPlans,
  name: r'nexusPlansProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nexusPlansHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NexusPlansRef = FutureProviderRef<PlanCatalog>;
String _$nexusUsageHash() => r'0cb4f4a3c1d852f4448d68caccab1f64508ed9d7';

/// Current-period usage vs. entitlements (requires sign-in).
///
/// Copied from [nexusUsage].
@ProviderFor(nexusUsage)
final nexusUsageProvider = AutoDisposeFutureProvider<UsageSnapshot>.internal(
  nexusUsage,
  name: r'nexusUsageProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nexusUsageHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NexusUsageRef = AutoDisposeFutureProviderRef<UsageSnapshot>;
String _$nexusAccountSummaryHash() =>
    r'716ee3dd3a4756945f500e61ca5e6a589e31ac0b';

/// The signed-in user's account + subscription summary.
///
/// Copied from [nexusAccountSummary].
@ProviderFor(nexusAccountSummary)
final nexusAccountSummaryProvider =
    AutoDisposeFutureProvider<AccountSummary>.internal(
      nexusAccountSummary,
      name: r'nexusAccountSummaryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$nexusAccountSummaryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NexusAccountSummaryRef = AutoDisposeFutureProviderRef<AccountSummary>;
String _$nexusGatewayBaseUrlHash() =>
    r'991bd162df89746d05cc654c666fb27ab906e302';

/// The gateway base URL (overridable). Defaults to the production gateway, but
/// hydrates from secure storage if the user has set an override.
///
/// Copied from [NexusGatewayBaseUrl].
@ProviderFor(NexusGatewayBaseUrl)
final nexusGatewayBaseUrlProvider =
    AutoDisposeNotifierProvider<NexusGatewayBaseUrl, String>.internal(
      NexusGatewayBaseUrl.new,
      name: r'nexusGatewayBaseUrlProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$nexusGatewayBaseUrlHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$NexusGatewayBaseUrl = AutoDisposeNotifier<String>;
String _$nexusAuthHash() => r'c9509733ee4563aa95438af89b76f61f4ea22b05';

/// Signed-in account state. Hydrates the token + cached identity from secure
/// storage on build, then exposes login / register / logout.
///
/// Copied from [NexusAuth].
@ProviderFor(NexusAuth)
final nexusAuthProvider =
    AutoDisposeNotifierProvider<NexusAuth, NexusAuthState>.internal(
      NexusAuth.new,
      name: r'nexusAuthProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$nexusAuthHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$NexusAuth = AutoDisposeNotifier<NexusAuthState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
