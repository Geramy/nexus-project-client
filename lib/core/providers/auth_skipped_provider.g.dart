// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_skipped_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the user chose "Skip for now" on the login screen — PERSISTED in
/// SharedPreferences so we don't prompt them to sign in on every launch.
///
/// Returns false by default and hydrates the saved value asynchronously, the
/// same sync-default + async-hydrate pattern as [AppThemeNotifier]. Signing in
/// or signing out is unaffected; this only suppresses the login wall.

@ProviderFor(AuthSkippedNotifier)
final authSkippedProvider = AuthSkippedNotifierProvider._();

/// Whether the user chose "Skip for now" on the login screen — PERSISTED in
/// SharedPreferences so we don't prompt them to sign in on every launch.
///
/// Returns false by default and hydrates the saved value asynchronously, the
/// same sync-default + async-hydrate pattern as [AppThemeNotifier]. Signing in
/// or signing out is unaffected; this only suppresses the login wall.
final class AuthSkippedNotifierProvider
    extends $NotifierProvider<AuthSkippedNotifier, bool> {
  /// Whether the user chose "Skip for now" on the login screen — PERSISTED in
  /// SharedPreferences so we don't prompt them to sign in on every launch.
  ///
  /// Returns false by default and hydrates the saved value asynchronously, the
  /// same sync-default + async-hydrate pattern as [AppThemeNotifier]. Signing in
  /// or signing out is unaffected; this only suppresses the login wall.
  AuthSkippedNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authSkippedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authSkippedNotifierHash();

  @$internal
  @override
  AuthSkippedNotifier create() => AuthSkippedNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$authSkippedNotifierHash() =>
    r'fdad5d9de8fc40627f2de4d2a4ad36c7340c598a';

/// Whether the user chose "Skip for now" on the login screen — PERSISTED in
/// SharedPreferences so we don't prompt them to sign in on every launch.
///
/// Returns false by default and hydrates the saved value asynchronously, the
/// same sync-default + async-hydrate pattern as [AppThemeNotifier]. Signing in
/// or signing out is unaffected; this only suppresses the login wall.

abstract class _$AuthSkippedNotifier extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
