// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lean_context_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(LeanContextNotifier)
final leanContextProvider = LeanContextNotifierProvider._();

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
final class LeanContextNotifierProvider
    extends $NotifierProvider<LeanContextNotifier, bool> {
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
  LeanContextNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'leanContextProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$leanContextNotifierHash();

  @$internal
  @override
  LeanContextNotifier create() => LeanContextNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$leanContextNotifierHash() =>
    r'ee7327ad85e4bcf9f20621cc4afb5ff6cf67d5ba';

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

abstract class _$LeanContextNotifier extends $Notifier<bool> {
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
