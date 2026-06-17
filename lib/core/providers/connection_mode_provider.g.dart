// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ConnectionModeNotifier)
final connectionModeProvider = ConnectionModeNotifierProvider._();

final class ConnectionModeNotifierProvider
    extends $NotifierProvider<ConnectionModeNotifier, ConnectionMode> {
  ConnectionModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionModeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionModeNotifierHash();

  @$internal
  @override
  ConnectionModeNotifier create() => ConnectionModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionMode>(value),
    );
  }
}

String _$connectionModeNotifierHash() =>
    r'70e420df5a8206f90677df41e848f5bc260cf9bf';

abstract class _$ConnectionModeNotifier extends $Notifier<ConnectionMode> {
  ConnectionMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ConnectionMode, ConnectionMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConnectionMode, ConnectionMode>,
              ConnectionMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
