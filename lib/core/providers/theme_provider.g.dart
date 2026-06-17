// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The user's selected app theme, persisted in SharedPreferences.
///
/// Defaults to [AppThemeChoice.defaultChoice] (the website-style "Nebula") on
/// first run, then hydrates the saved choice asynchronously — mirroring the
/// persistence pattern used by [PanelLayoutNotifier] in app_shell_provider.dart.

@ProviderFor(AppThemeNotifier)
final appThemeProvider = AppThemeNotifierProvider._();

/// The user's selected app theme, persisted in SharedPreferences.
///
/// Defaults to [AppThemeChoice.defaultChoice] (the website-style "Nebula") on
/// first run, then hydrates the saved choice asynchronously — mirroring the
/// persistence pattern used by [PanelLayoutNotifier] in app_shell_provider.dart.
final class AppThemeNotifierProvider
    extends $NotifierProvider<AppThemeNotifier, AppThemeChoice> {
  /// The user's selected app theme, persisted in SharedPreferences.
  ///
  /// Defaults to [AppThemeChoice.defaultChoice] (the website-style "Nebula") on
  /// first run, then hydrates the saved choice asynchronously — mirroring the
  /// persistence pattern used by [PanelLayoutNotifier] in app_shell_provider.dart.
  AppThemeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appThemeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appThemeNotifierHash();

  @$internal
  @override
  AppThemeNotifier create() => AppThemeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppThemeChoice value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppThemeChoice>(value),
    );
  }
}

String _$appThemeNotifierHash() => r'05885e16df7d20a2655e028f7fdb46d7b18b01ce';

/// The user's selected app theme, persisted in SharedPreferences.
///
/// Defaults to [AppThemeChoice.defaultChoice] (the website-style "Nebula") on
/// first run, then hydrates the saved choice asynchronously — mirroring the
/// persistence pattern used by [PanelLayoutNotifier] in app_shell_provider.dart.

abstract class _$AppThemeNotifier extends $Notifier<AppThemeChoice> {
  AppThemeChoice build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AppThemeChoice, AppThemeChoice>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppThemeChoice, AppThemeChoice>,
              AppThemeChoice,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
