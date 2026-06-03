// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lean_context_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$leanContextNotifierHash() =>
    r'a4df9a2e506665ef77391bc938ff65999d4fcbe4';

/// Whether "Lean context" mode is on — PERSISTED in SharedPreferences.
///
/// When ON (default), the AI flows reconstruct state from the harness (the DB)
/// instead of replaying full conversations:
///   - the Setup interview sends a board-state summary + a short rolling window
///     of turns instead of the whole transcript, and drops the interview context
///     entirely once plans are finalized;
///   - the Coordinator exposes only its core task/plan tools by default and pulls
///     in file/git/CI tool groups on demand via `request_tools`.
///
/// When OFF, both flows fall back to the previous behavior (full history, all
/// tools every call). Toggle it in Account → Lean context to compare.
///
/// Copied from [LeanContextNotifier].
@ProviderFor(LeanContextNotifier)
final leanContextNotifierProvider =
    AutoDisposeNotifierProvider<LeanContextNotifier, bool>.internal(
      LeanContextNotifier.new,
      name: r'leanContextNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$leanContextNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LeanContextNotifier = AutoDisposeNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
