// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appThemeNotifierHash() => r'a10c904051bd2022097c8e9cc8b359159b7ab8f7';

/// The user's selected app theme, persisted in SharedPreferences.
///
/// Defaults to [AppThemeChoice.defaultChoice] (the website-style "Nebula") on
/// first run, then hydrates the saved choice asynchronously — mirroring the
/// persistence pattern used by [PanelLayoutNotifier] in app_shell_provider.dart.
///
/// Copied from [AppThemeNotifier].
@ProviderFor(AppThemeNotifier)
final appThemeNotifierProvider =
    AutoDisposeNotifierProvider<AppThemeNotifier, AppThemeChoice>.internal(
      AppThemeNotifier.new,
      name: r'appThemeNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$appThemeNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppThemeNotifier = AutoDisposeNotifier<AppThemeChoice>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
