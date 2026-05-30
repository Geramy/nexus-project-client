// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inference_servers_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$inferenceServersNotifierHash() =>
    r'3237391e86c3800768e4156477000604900eef88';

/// @deprecated
/// This global notifier has been replaced by client-scoped Drift storage
/// (see inferenceServersForClientProvider in database_provider.dart).
///
/// It is kept only for backward compatibility with any remaining references
/// during the multi-tenancy migration. New code should use the Drift-backed,
/// client-scoped providers instead.
///
/// Copied from [InferenceServersNotifier].
@ProviderFor(InferenceServersNotifier)
final inferenceServersNotifierProvider =
    AutoDisposeNotifierProvider<
      InferenceServersNotifier,
      List<InferenceServer>
    >.internal(
      InferenceServersNotifier.new,
      name: r'inferenceServersNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$inferenceServersNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$InferenceServersNotifier = AutoDisposeNotifier<List<InferenceServer>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
