// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_skipped_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authSkippedNotifierHash() =>
    r'0a4b08d4d0856fc7aa9a99c73fcb179557a94be7';

/// Whether the user chose "Skip for now" on the login screen — PERSISTED in
/// SharedPreferences so we don't prompt them to sign in on every launch.
///
/// Returns false by default and hydrates the saved value asynchronously, the
/// same sync-default + async-hydrate pattern as [AppThemeNotifier]. Signing in
/// or signing out is unaffected; this only suppresses the login wall.
///
/// Copied from [AuthSkippedNotifier].
@ProviderFor(AuthSkippedNotifier)
final authSkippedNotifierProvider =
    AutoDisposeNotifierProvider<AuthSkippedNotifier, bool>.internal(
      AuthSkippedNotifier.new,
      name: r'authSkippedNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$authSkippedNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AuthSkippedNotifier = AutoDisposeNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
