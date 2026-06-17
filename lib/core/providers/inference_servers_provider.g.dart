// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inference_servers_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// @deprecated
/// This global notifier has been replaced by client-scoped Drift storage
/// (see inferenceServersForClientProvider in database_provider.dart).
///
/// It is kept only for backward compatibility with any remaining references
/// during the multi-tenancy migration. New code should use the Drift-backed,
/// client-scoped providers instead.

@ProviderFor(InferenceServersNotifier)
final inferenceServersProvider = InferenceServersNotifierProvider._();

/// @deprecated
/// This global notifier has been replaced by client-scoped Drift storage
/// (see inferenceServersForClientProvider in database_provider.dart).
///
/// It is kept only for backward compatibility with any remaining references
/// during the multi-tenancy migration. New code should use the Drift-backed,
/// client-scoped providers instead.
final class InferenceServersNotifierProvider
    extends $NotifierProvider<InferenceServersNotifier, List<InferenceServer>> {
  /// @deprecated
  /// This global notifier has been replaced by client-scoped Drift storage
  /// (see inferenceServersForClientProvider in database_provider.dart).
  ///
  /// It is kept only for backward compatibility with any remaining references
  /// during the multi-tenancy migration. New code should use the Drift-backed,
  /// client-scoped providers instead.
  InferenceServersNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inferenceServersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inferenceServersNotifierHash();

  @$internal
  @override
  InferenceServersNotifier create() => InferenceServersNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<InferenceServer> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<InferenceServer>>(value),
    );
  }
}

String _$inferenceServersNotifierHash() =>
    r'3237391e86c3800768e4156477000604900eef88';

/// @deprecated
/// This global notifier has been replaced by client-scoped Drift storage
/// (see inferenceServersForClientProvider in database_provider.dart).
///
/// It is kept only for backward compatibility with any remaining references
/// during the multi-tenancy migration. New code should use the Drift-backed,
/// client-scoped providers instead.

abstract class _$InferenceServersNotifier
    extends $Notifier<List<InferenceServer>> {
  List<InferenceServer> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<InferenceServer>, List<InferenceServer>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<InferenceServer>, List<InferenceServer>>,
              List<InferenceServer>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
