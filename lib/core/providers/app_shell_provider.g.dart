// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_shell_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$currentMainViewHash() => r'7645f9811f8558e5c58ec9c3bb7cc55b0d2a9f06';

/// See also [CurrentMainView].
@ProviderFor(CurrentMainView)
final currentMainViewProvider =
    AutoDisposeNotifierProvider<CurrentMainView, MainView>.internal(
      CurrentMainView.new,
      name: r'currentMainViewProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$currentMainViewHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$CurrentMainView = AutoDisposeNotifier<MainView>;
String _$selectedTaskIdNotifierHash() =>
    r'cd8d00b7f5de6cdebbb18fbc7d789d7ee416113d';

/// See also [SelectedTaskIdNotifier].
@ProviderFor(SelectedTaskIdNotifier)
final selectedTaskIdNotifierProvider =
    AutoDisposeNotifierProvider<SelectedTaskIdNotifier, int?>.internal(
      SelectedTaskIdNotifier.new,
      name: r'selectedTaskIdNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$selectedTaskIdNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SelectedTaskIdNotifier = AutoDisposeNotifier<int?>;
String _$currentClientIdHash() => r'd6e260afe729c1d0ef84da228525f9da7cdd2045';

/// Current selected client (top level of the hierarchy)
///
/// Copied from [CurrentClientId].
@ProviderFor(CurrentClientId)
final currentClientIdProvider =
    AutoDisposeNotifierProvider<CurrentClientId, int>.internal(
      CurrentClientId.new,
      name: r'currentClientIdProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$currentClientIdHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$CurrentClientId = AutoDisposeNotifier<int>;
String _$currentProjectIdHash() => r'dc0b7f1476dc7afcffe0097741f1d95a196e9136';

/// Current selected project (part of Client → Projects → Tasks hierarchy)
///
/// Copied from [CurrentProjectId].
@ProviderFor(CurrentProjectId)
final currentProjectIdProvider =
    AutoDisposeNotifierProvider<CurrentProjectId, int>.internal(
      CurrentProjectId.new,
      name: r'currentProjectIdProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$currentProjectIdHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$CurrentProjectId = AutoDisposeNotifier<int>;
String _$connectionModeNotifierHash() =>
    r'ec812b9d5e0ba75c816fd86cd1914a947b9e832e';

/// See also [ConnectionModeNotifier].
@ProviderFor(ConnectionModeNotifier)
final connectionModeNotifierProvider =
    AutoDisposeNotifierProvider<ConnectionModeNotifier, String>.internal(
      ConnectionModeNotifier.new,
      name: r'connectionModeNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$connectionModeNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ConnectionModeNotifier = AutoDisposeNotifier<String>;
String _$selectedPersonaNotifierHash() =>
    r'e83cc09624e5cc0b3e96ff816f435412ab54ddfb';

/// See also [SelectedPersonaNotifier].
@ProviderFor(SelectedPersonaNotifier)
final selectedPersonaNotifierProvider =
    AutoDisposeNotifierProvider<
      SelectedPersonaNotifier,
      EditingPersona?
    >.internal(
      SelectedPersonaNotifier.new,
      name: r'selectedPersonaNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$selectedPersonaNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SelectedPersonaNotifier = AutoDisposeNotifier<EditingPersona?>;
String _$currentChatSessionHash() =>
    r'474108968b9d2a27768cda1173df5581f4a26bd3';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$CurrentChatSession extends BuildlessAutoDisposeNotifier<int?> {
  late final int projectId;

  int? build(int projectId);
}

/// The active Coordinator chat session id for a given project (right-panel
/// selection). Family keyed by projectId so each project has its own active
/// session. The coordinator chat screen opens this session; the Chat Sessions
/// sidebar selects/creates it.
///
/// Copied from [CurrentChatSession].
@ProviderFor(CurrentChatSession)
const currentChatSessionProvider = CurrentChatSessionFamily();

/// The active Coordinator chat session id for a given project (right-panel
/// selection). Family keyed by projectId so each project has its own active
/// session. The coordinator chat screen opens this session; the Chat Sessions
/// sidebar selects/creates it.
///
/// Copied from [CurrentChatSession].
class CurrentChatSessionFamily extends Family<int?> {
  /// The active Coordinator chat session id for a given project (right-panel
  /// selection). Family keyed by projectId so each project has its own active
  /// session. The coordinator chat screen opens this session; the Chat Sessions
  /// sidebar selects/creates it.
  ///
  /// Copied from [CurrentChatSession].
  const CurrentChatSessionFamily();

  /// The active Coordinator chat session id for a given project (right-panel
  /// selection). Family keyed by projectId so each project has its own active
  /// session. The coordinator chat screen opens this session; the Chat Sessions
  /// sidebar selects/creates it.
  ///
  /// Copied from [CurrentChatSession].
  CurrentChatSessionProvider call(int projectId) {
    return CurrentChatSessionProvider(projectId);
  }

  @override
  CurrentChatSessionProvider getProviderOverride(
    covariant CurrentChatSessionProvider provider,
  ) {
    return call(provider.projectId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'currentChatSessionProvider';
}

/// The active Coordinator chat session id for a given project (right-panel
/// selection). Family keyed by projectId so each project has its own active
/// session. The coordinator chat screen opens this session; the Chat Sessions
/// sidebar selects/creates it.
///
/// Copied from [CurrentChatSession].
class CurrentChatSessionProvider
    extends AutoDisposeNotifierProviderImpl<CurrentChatSession, int?> {
  /// The active Coordinator chat session id for a given project (right-panel
  /// selection). Family keyed by projectId so each project has its own active
  /// session. The coordinator chat screen opens this session; the Chat Sessions
  /// sidebar selects/creates it.
  ///
  /// Copied from [CurrentChatSession].
  CurrentChatSessionProvider(int projectId)
    : this._internal(
        () => CurrentChatSession()..projectId = projectId,
        from: currentChatSessionProvider,
        name: r'currentChatSessionProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$currentChatSessionHash,
        dependencies: CurrentChatSessionFamily._dependencies,
        allTransitiveDependencies:
            CurrentChatSessionFamily._allTransitiveDependencies,
        projectId: projectId,
      );

  CurrentChatSessionProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.projectId,
  }) : super.internal();

  final int projectId;

  @override
  int? runNotifierBuild(covariant CurrentChatSession notifier) {
    return notifier.build(projectId);
  }

  @override
  Override overrideWith(CurrentChatSession Function() create) {
    return ProviderOverride(
      origin: this,
      override: CurrentChatSessionProvider._internal(
        () => create()..projectId = projectId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        projectId: projectId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<CurrentChatSession, int?> createElement() {
    return _CurrentChatSessionProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentChatSessionProvider && other.projectId == projectId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, projectId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CurrentChatSessionRef on AutoDisposeNotifierProviderRef<int?> {
  /// The parameter `projectId` of this provider.
  int get projectId;
}

class _CurrentChatSessionProviderElement
    extends AutoDisposeNotifierProviderElement<CurrentChatSession, int?>
    with CurrentChatSessionRef {
  _CurrentChatSessionProviderElement(super.provider);

  @override
  int get projectId => (origin as CurrentChatSessionProvider).projectId;
}

String _$openPlanNotifierHash() => r'14ed91b11239ac2e5da57bd58b3aa563f36db545';

/// The plan currently opened in the Project Plans workspace (workspace path,
/// e.g. `/PLANS/Roadmap.md`), set by clicking a plan file in the explorer.
/// Null = nothing open.
///
/// Copied from [OpenPlanNotifier].
@ProviderFor(OpenPlanNotifier)
final openPlanNotifierProvider =
    AutoDisposeNotifierProvider<OpenPlanNotifier, String?>.internal(
      OpenPlanNotifier.new,
      name: r'openPlanNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$openPlanNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$OpenPlanNotifier = AutoDisposeNotifier<String?>;
String _$planModeNotifierHash() => r'098ce815492356cc7aed11814e6e1f5f430cab69';

/// See also [PlanModeNotifier].
@ProviderFor(PlanModeNotifier)
final planModeNotifierProvider =
    AutoDisposeNotifierProvider<PlanModeNotifier, PlanMode>.internal(
      PlanModeNotifier.new,
      name: r'planModeNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$planModeNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PlanModeNotifier = AutoDisposeNotifier<PlanMode>;
String _$panelLayoutNotifierHash() =>
    r'9a7b76abc448ecf91ae7b05293f13544a40bd2c2';

/// Persistent right-panel width per MainView.
/// Stored in SharedPreferences so layout survives app restarts.
///
/// Copied from [PanelLayoutNotifier].
@ProviderFor(PanelLayoutNotifier)
final panelLayoutNotifierProvider =
    AutoDisposeNotifierProvider<
      PanelLayoutNotifier,
      Map<MainView, double>
    >.internal(
      PanelLayoutNotifier.new,
      name: r'panelLayoutNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$panelLayoutNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PanelLayoutNotifier = AutoDisposeNotifier<Map<MainView, double>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
