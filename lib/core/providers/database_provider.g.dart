// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$nexusDatabaseHash() => r'ffb7f6d7c9c76ef9f1eaa9a81db862b5be051e01';

/// See also [nexusDatabase].
@ProviderFor(nexusDatabase)
final nexusDatabaseProvider = Provider<NexusDatabase>.internal(
  nexusDatabase,
  name: r'nexusDatabaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$nexusDatabaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NexusDatabaseRef = ProviderRef<NexusDatabase>;
String _$allClientsHash() => r'1ce374b1dd4c2016113e9fbfba8a194e5950a331';

/// Reactive list of all clients (updates automatically on any change)
///
/// Copied from [allClients].
@ProviderFor(allClients)
final allClientsProvider = StreamProvider<List<Client>>.internal(
  allClients,
  name: r'allClientsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$allClientsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AllClientsRef = StreamProviderRef<List<Client>>;
String _$projectsForClientHash() => r'c650d9e4e10b8c6481c52292ab5eaf554c404e29';

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

/// Reactive list of projects for a specific client
///
/// Copied from [projectsForClient].
@ProviderFor(projectsForClient)
const projectsForClientProvider = ProjectsForClientFamily();

/// Reactive list of projects for a specific client
///
/// Copied from [projectsForClient].
class ProjectsForClientFamily extends Family<AsyncValue<List<Project>>> {
  /// Reactive list of projects for a specific client
  ///
  /// Copied from [projectsForClient].
  const ProjectsForClientFamily();

  /// Reactive list of projects for a specific client
  ///
  /// Copied from [projectsForClient].
  ProjectsForClientProvider call(int clientId) {
    return ProjectsForClientProvider(clientId);
  }

  @override
  ProjectsForClientProvider getProviderOverride(
    covariant ProjectsForClientProvider provider,
  ) {
    return call(provider.clientId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'projectsForClientProvider';
}

/// Reactive list of projects for a specific client
///
/// Copied from [projectsForClient].
class ProjectsForClientProvider extends StreamProvider<List<Project>> {
  /// Reactive list of projects for a specific client
  ///
  /// Copied from [projectsForClient].
  ProjectsForClientProvider(int clientId)
    : this._internal(
        (ref) => projectsForClient(ref as ProjectsForClientRef, clientId),
        from: projectsForClientProvider,
        name: r'projectsForClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$projectsForClientHash,
        dependencies: ProjectsForClientFamily._dependencies,
        allTransitiveDependencies:
            ProjectsForClientFamily._allTransitiveDependencies,
        clientId: clientId,
      );

  ProjectsForClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clientId,
  }) : super.internal();

  final int clientId;

  @override
  Override overrideWith(
    Stream<List<Project>> Function(ProjectsForClientRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ProjectsForClientProvider._internal(
        (ref) => create(ref as ProjectsForClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clientId: clientId,
      ),
    );
  }

  @override
  StreamProviderElement<List<Project>> createElement() {
    return _ProjectsForClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectsForClientProvider && other.clientId == clientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ProjectsForClientRef on StreamProviderRef<List<Project>> {
  /// The parameter `clientId` of this provider.
  int get clientId;
}

class _ProjectsForClientProviderElement
    extends StreamProviderElement<List<Project>>
    with ProjectsForClientRef {
  _ProjectsForClientProviderElement(super.provider);

  @override
  int get clientId => (origin as ProjectsForClientProvider).clientId;
}

String _$allTasksForProjectHash() =>
    r'e9cd8718d9901d64b1e9ab41b4d84a0ae6d9e450';

/// Reactive all tasks for a project (flat list, good for building trees client-side)
///
/// Copied from [allTasksForProject].
@ProviderFor(allTasksForProject)
const allTasksForProjectProvider = AllTasksForProjectFamily();

/// Reactive all tasks for a project (flat list, good for building trees client-side)
///
/// Copied from [allTasksForProject].
class AllTasksForProjectFamily extends Family<AsyncValue<List<Task>>> {
  /// Reactive all tasks for a project (flat list, good for building trees client-side)
  ///
  /// Copied from [allTasksForProject].
  const AllTasksForProjectFamily();

  /// Reactive all tasks for a project (flat list, good for building trees client-side)
  ///
  /// Copied from [allTasksForProject].
  AllTasksForProjectProvider call(int projectId) {
    return AllTasksForProjectProvider(projectId);
  }

  @override
  AllTasksForProjectProvider getProviderOverride(
    covariant AllTasksForProjectProvider provider,
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
  String? get name => r'allTasksForProjectProvider';
}

/// Reactive all tasks for a project (flat list, good for building trees client-side)
///
/// Copied from [allTasksForProject].
class AllTasksForProjectProvider extends StreamProvider<List<Task>> {
  /// Reactive all tasks for a project (flat list, good for building trees client-side)
  ///
  /// Copied from [allTasksForProject].
  AllTasksForProjectProvider(int projectId)
    : this._internal(
        (ref) => allTasksForProject(ref as AllTasksForProjectRef, projectId),
        from: allTasksForProjectProvider,
        name: r'allTasksForProjectProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$allTasksForProjectHash,
        dependencies: AllTasksForProjectFamily._dependencies,
        allTransitiveDependencies:
            AllTasksForProjectFamily._allTransitiveDependencies,
        projectId: projectId,
      );

  AllTasksForProjectProvider._internal(
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
  Override overrideWith(
    Stream<List<Task>> Function(AllTasksForProjectRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: AllTasksForProjectProvider._internal(
        (ref) => create(ref as AllTasksForProjectRef),
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
  StreamProviderElement<List<Task>> createElement() {
    return _AllTasksForProjectProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is AllTasksForProjectProvider && other.projectId == projectId;
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
mixin AllTasksForProjectRef on StreamProviderRef<List<Task>> {
  /// The parameter `projectId` of this provider.
  int get projectId;
}

class _AllTasksForProjectProviderElement
    extends StreamProviderElement<List<Task>>
    with AllTasksForProjectRef {
  _AllTasksForProjectProviderElement(super.provider);

  @override
  int get projectId => (origin as AllTasksForProjectProvider).projectId;
}

String _$inferenceServersForClientHash() =>
    r'87ba937a3b9914f262881890309bfb4aeeafc914';

/// Reactive list of Inference Servers for the current Client (multi-tenancy)
///
/// Copied from [inferenceServersForClient].
@ProviderFor(inferenceServersForClient)
const inferenceServersForClientProvider = InferenceServersForClientFamily();

/// Reactive list of Inference Servers for the current Client (multi-tenancy)
///
/// Copied from [inferenceServersForClient].
class InferenceServersForClientFamily
    extends Family<AsyncValue<List<InferenceServer>>> {
  /// Reactive list of Inference Servers for the current Client (multi-tenancy)
  ///
  /// Copied from [inferenceServersForClient].
  const InferenceServersForClientFamily();

  /// Reactive list of Inference Servers for the current Client (multi-tenancy)
  ///
  /// Copied from [inferenceServersForClient].
  InferenceServersForClientProvider call(int clientId) {
    return InferenceServersForClientProvider(clientId);
  }

  @override
  InferenceServersForClientProvider getProviderOverride(
    covariant InferenceServersForClientProvider provider,
  ) {
    return call(provider.clientId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'inferenceServersForClientProvider';
}

/// Reactive list of Inference Servers for the current Client (multi-tenancy)
///
/// Copied from [inferenceServersForClient].
class InferenceServersForClientProvider
    extends StreamProvider<List<InferenceServer>> {
  /// Reactive list of Inference Servers for the current Client (multi-tenancy)
  ///
  /// Copied from [inferenceServersForClient].
  InferenceServersForClientProvider(int clientId)
    : this._internal(
        (ref) => inferenceServersForClient(
          ref as InferenceServersForClientRef,
          clientId,
        ),
        from: inferenceServersForClientProvider,
        name: r'inferenceServersForClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$inferenceServersForClientHash,
        dependencies: InferenceServersForClientFamily._dependencies,
        allTransitiveDependencies:
            InferenceServersForClientFamily._allTransitiveDependencies,
        clientId: clientId,
      );

  InferenceServersForClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clientId,
  }) : super.internal();

  final int clientId;

  @override
  Override overrideWith(
    Stream<List<InferenceServer>> Function(
      InferenceServersForClientRef provider,
    )
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: InferenceServersForClientProvider._internal(
        (ref) => create(ref as InferenceServersForClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clientId: clientId,
      ),
    );
  }

  @override
  StreamProviderElement<List<InferenceServer>> createElement() {
    return _InferenceServersForClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is InferenceServersForClientProvider &&
        other.clientId == clientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin InferenceServersForClientRef on StreamProviderRef<List<InferenceServer>> {
  /// The parameter `clientId` of this provider.
  int get clientId;
}

class _InferenceServersForClientProviderElement
    extends StreamProviderElement<List<InferenceServer>>
    with InferenceServersForClientRef {
  _InferenceServersForClientProviderElement(super.provider);

  @override
  int get clientId => (origin as InferenceServersForClientProvider).clientId;
}

String _$agentPersonasForClientHash() =>
    r'238ddf8ed4669f234cb44f523c13e4c3fda30712';

/// Reactive list of Agent Personas for the current Client (multi-tenancy)
///
/// Copied from [agentPersonasForClient].
@ProviderFor(agentPersonasForClient)
const agentPersonasForClientProvider = AgentPersonasForClientFamily();

/// Reactive list of Agent Personas for the current Client (multi-tenancy)
///
/// Copied from [agentPersonasForClient].
class AgentPersonasForClientFamily
    extends Family<AsyncValue<List<AgentPersona>>> {
  /// Reactive list of Agent Personas for the current Client (multi-tenancy)
  ///
  /// Copied from [agentPersonasForClient].
  const AgentPersonasForClientFamily();

  /// Reactive list of Agent Personas for the current Client (multi-tenancy)
  ///
  /// Copied from [agentPersonasForClient].
  AgentPersonasForClientProvider call(int clientId) {
    return AgentPersonasForClientProvider(clientId);
  }

  @override
  AgentPersonasForClientProvider getProviderOverride(
    covariant AgentPersonasForClientProvider provider,
  ) {
    return call(provider.clientId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'agentPersonasForClientProvider';
}

/// Reactive list of Agent Personas for the current Client (multi-tenancy)
///
/// Copied from [agentPersonasForClient].
class AgentPersonasForClientProvider
    extends StreamProvider<List<AgentPersona>> {
  /// Reactive list of Agent Personas for the current Client (multi-tenancy)
  ///
  /// Copied from [agentPersonasForClient].
  AgentPersonasForClientProvider(int clientId)
    : this._internal(
        (ref) =>
            agentPersonasForClient(ref as AgentPersonasForClientRef, clientId),
        from: agentPersonasForClientProvider,
        name: r'agentPersonasForClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$agentPersonasForClientHash,
        dependencies: AgentPersonasForClientFamily._dependencies,
        allTransitiveDependencies:
            AgentPersonasForClientFamily._allTransitiveDependencies,
        clientId: clientId,
      );

  AgentPersonasForClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clientId,
  }) : super.internal();

  final int clientId;

  @override
  Override overrideWith(
    Stream<List<AgentPersona>> Function(AgentPersonasForClientRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: AgentPersonasForClientProvider._internal(
        (ref) => create(ref as AgentPersonasForClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clientId: clientId,
      ),
    );
  }

  @override
  StreamProviderElement<List<AgentPersona>> createElement() {
    return _AgentPersonasForClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentPersonasForClientProvider &&
        other.clientId == clientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin AgentPersonasForClientRef on StreamProviderRef<List<AgentPersona>> {
  /// The parameter `clientId` of this provider.
  int get clientId;
}

class _AgentPersonasForClientProviderElement
    extends StreamProviderElement<List<AgentPersona>>
    with AgentPersonasForClientRef {
  _AgentPersonasForClientProviderElement(super.provider);

  @override
  int get clientId => (origin as AgentPersonasForClientProvider).clientId;
}

String _$deploymentsForClientHash() =>
    r'c59c5db912b3fa480a3e4c95965299f70bea281f';

/// Reactive Deployments for client (Phase 1 placeholder)
///
/// Copied from [deploymentsForClient].
@ProviderFor(deploymentsForClient)
const deploymentsForClientProvider = DeploymentsForClientFamily();

/// Reactive Deployments for client (Phase 1 placeholder)
///
/// Copied from [deploymentsForClient].
class DeploymentsForClientFamily extends Family<AsyncValue<List<Deployment>>> {
  /// Reactive Deployments for client (Phase 1 placeholder)
  ///
  /// Copied from [deploymentsForClient].
  const DeploymentsForClientFamily();

  /// Reactive Deployments for client (Phase 1 placeholder)
  ///
  /// Copied from [deploymentsForClient].
  DeploymentsForClientProvider call(int clientId) {
    return DeploymentsForClientProvider(clientId);
  }

  @override
  DeploymentsForClientProvider getProviderOverride(
    covariant DeploymentsForClientProvider provider,
  ) {
    return call(provider.clientId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'deploymentsForClientProvider';
}

/// Reactive Deployments for client (Phase 1 placeholder)
///
/// Copied from [deploymentsForClient].
class DeploymentsForClientProvider extends StreamProvider<List<Deployment>> {
  /// Reactive Deployments for client (Phase 1 placeholder)
  ///
  /// Copied from [deploymentsForClient].
  DeploymentsForClientProvider(int clientId)
    : this._internal(
        (ref) => deploymentsForClient(ref as DeploymentsForClientRef, clientId),
        from: deploymentsForClientProvider,
        name: r'deploymentsForClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$deploymentsForClientHash,
        dependencies: DeploymentsForClientFamily._dependencies,
        allTransitiveDependencies:
            DeploymentsForClientFamily._allTransitiveDependencies,
        clientId: clientId,
      );

  DeploymentsForClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clientId,
  }) : super.internal();

  final int clientId;

  @override
  Override overrideWith(
    Stream<List<Deployment>> Function(DeploymentsForClientRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: DeploymentsForClientProvider._internal(
        (ref) => create(ref as DeploymentsForClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clientId: clientId,
      ),
    );
  }

  @override
  StreamProviderElement<List<Deployment>> createElement() {
    return _DeploymentsForClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DeploymentsForClientProvider && other.clientId == clientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DeploymentsForClientRef on StreamProviderRef<List<Deployment>> {
  /// The parameter `clientId` of this provider.
  int get clientId;
}

class _DeploymentsForClientProviderElement
    extends StreamProviderElement<List<Deployment>>
    with DeploymentsForClientRef {
  _DeploymentsForClientProviderElement(super.provider);

  @override
  int get clientId => (origin as DeploymentsForClientProvider).clientId;
}

String _$activityLogsForClientHash() =>
    r'c8cab3cf5303a2955ad21374787fdfe7f5b7b659';

/// Reactive Activity Logs for client (Phase 1 placeholder)
///
/// Copied from [activityLogsForClient].
@ProviderFor(activityLogsForClient)
const activityLogsForClientProvider = ActivityLogsForClientFamily();

/// Reactive Activity Logs for client (Phase 1 placeholder)
///
/// Copied from [activityLogsForClient].
class ActivityLogsForClientFamily
    extends Family<AsyncValue<List<ActivityLog>>> {
  /// Reactive Activity Logs for client (Phase 1 placeholder)
  ///
  /// Copied from [activityLogsForClient].
  const ActivityLogsForClientFamily();

  /// Reactive Activity Logs for client (Phase 1 placeholder)
  ///
  /// Copied from [activityLogsForClient].
  ActivityLogsForClientProvider call(int clientId) {
    return ActivityLogsForClientProvider(clientId);
  }

  @override
  ActivityLogsForClientProvider getProviderOverride(
    covariant ActivityLogsForClientProvider provider,
  ) {
    return call(provider.clientId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'activityLogsForClientProvider';
}

/// Reactive Activity Logs for client (Phase 1 placeholder)
///
/// Copied from [activityLogsForClient].
class ActivityLogsForClientProvider extends StreamProvider<List<ActivityLog>> {
  /// Reactive Activity Logs for client (Phase 1 placeholder)
  ///
  /// Copied from [activityLogsForClient].
  ActivityLogsForClientProvider(int clientId)
    : this._internal(
        (ref) =>
            activityLogsForClient(ref as ActivityLogsForClientRef, clientId),
        from: activityLogsForClientProvider,
        name: r'activityLogsForClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$activityLogsForClientHash,
        dependencies: ActivityLogsForClientFamily._dependencies,
        allTransitiveDependencies:
            ActivityLogsForClientFamily._allTransitiveDependencies,
        clientId: clientId,
      );

  ActivityLogsForClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clientId,
  }) : super.internal();

  final int clientId;

  @override
  Override overrideWith(
    Stream<List<ActivityLog>> Function(ActivityLogsForClientRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ActivityLogsForClientProvider._internal(
        (ref) => create(ref as ActivityLogsForClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clientId: clientId,
      ),
    );
  }

  @override
  StreamProviderElement<List<ActivityLog>> createElement() {
    return _ActivityLogsForClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityLogsForClientProvider && other.clientId == clientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ActivityLogsForClientRef on StreamProviderRef<List<ActivityLog>> {
  /// The parameter `clientId` of this provider.
  int get clientId;
}

class _ActivityLogsForClientProviderElement
    extends StreamProviderElement<List<ActivityLog>>
    with ActivityLogsForClientRef {
  _ActivityLogsForClientProviderElement(super.provider);

  @override
  int get clientId => (origin as ActivityLogsForClientProvider).clientId;
}

String _$ciRunsForClientHash() => r'5fbb37c740890a47d73764ee529eb619d8ecdcfb';

/// Reactive CI Runs for client (Phase 1 placeholder)
///
/// Copied from [ciRunsForClient].
@ProviderFor(ciRunsForClient)
const ciRunsForClientProvider = CiRunsForClientFamily();

/// Reactive CI Runs for client (Phase 1 placeholder)
///
/// Copied from [ciRunsForClient].
class CiRunsForClientFamily extends Family<AsyncValue<List<CiRun>>> {
  /// Reactive CI Runs for client (Phase 1 placeholder)
  ///
  /// Copied from [ciRunsForClient].
  const CiRunsForClientFamily();

  /// Reactive CI Runs for client (Phase 1 placeholder)
  ///
  /// Copied from [ciRunsForClient].
  CiRunsForClientProvider call(int clientId) {
    return CiRunsForClientProvider(clientId);
  }

  @override
  CiRunsForClientProvider getProviderOverride(
    covariant CiRunsForClientProvider provider,
  ) {
    return call(provider.clientId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'ciRunsForClientProvider';
}

/// Reactive CI Runs for client (Phase 1 placeholder)
///
/// Copied from [ciRunsForClient].
class CiRunsForClientProvider extends StreamProvider<List<CiRun>> {
  /// Reactive CI Runs for client (Phase 1 placeholder)
  ///
  /// Copied from [ciRunsForClient].
  CiRunsForClientProvider(int clientId)
    : this._internal(
        (ref) => ciRunsForClient(ref as CiRunsForClientRef, clientId),
        from: ciRunsForClientProvider,
        name: r'ciRunsForClientProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$ciRunsForClientHash,
        dependencies: CiRunsForClientFamily._dependencies,
        allTransitiveDependencies:
            CiRunsForClientFamily._allTransitiveDependencies,
        clientId: clientId,
      );

  CiRunsForClientProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.clientId,
  }) : super.internal();

  final int clientId;

  @override
  Override overrideWith(
    Stream<List<CiRun>> Function(CiRunsForClientRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CiRunsForClientProvider._internal(
        (ref) => create(ref as CiRunsForClientRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        clientId: clientId,
      ),
    );
  }

  @override
  StreamProviderElement<List<CiRun>> createElement() {
    return _CiRunsForClientProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CiRunsForClientProvider && other.clientId == clientId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, clientId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CiRunsForClientRef on StreamProviderRef<List<CiRun>> {
  /// The parameter `clientId` of this provider.
  int get clientId;
}

class _CiRunsForClientProviderElement extends StreamProviderElement<List<CiRun>>
    with CiRunsForClientRef {
  _CiRunsForClientProviderElement(super.provider);

  @override
  int get clientId => (origin as CiRunsForClientProvider).clientId;
}

String _$chatSessionsForProjectHash() =>
    r'b5d0acf24fef8763b68313bec689ad1624ed7bd1';

/// Reactive Coordinator chat sessions for a project (Client → Project → Session).
///
/// Copied from [chatSessionsForProject].
@ProviderFor(chatSessionsForProject)
const chatSessionsForProjectProvider = ChatSessionsForProjectFamily();

/// Reactive Coordinator chat sessions for a project (Client → Project → Session).
///
/// Copied from [chatSessionsForProject].
class ChatSessionsForProjectFamily
    extends Family<AsyncValue<List<ChatSession>>> {
  /// Reactive Coordinator chat sessions for a project (Client → Project → Session).
  ///
  /// Copied from [chatSessionsForProject].
  const ChatSessionsForProjectFamily();

  /// Reactive Coordinator chat sessions for a project (Client → Project → Session).
  ///
  /// Copied from [chatSessionsForProject].
  ChatSessionsForProjectProvider call(int projectId) {
    return ChatSessionsForProjectProvider(projectId);
  }

  @override
  ChatSessionsForProjectProvider getProviderOverride(
    covariant ChatSessionsForProjectProvider provider,
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
  String? get name => r'chatSessionsForProjectProvider';
}

/// Reactive Coordinator chat sessions for a project (Client → Project → Session).
///
/// Copied from [chatSessionsForProject].
class ChatSessionsForProjectProvider extends StreamProvider<List<ChatSession>> {
  /// Reactive Coordinator chat sessions for a project (Client → Project → Session).
  ///
  /// Copied from [chatSessionsForProject].
  ChatSessionsForProjectProvider(int projectId)
    : this._internal(
        (ref) =>
            chatSessionsForProject(ref as ChatSessionsForProjectRef, projectId),
        from: chatSessionsForProjectProvider,
        name: r'chatSessionsForProjectProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$chatSessionsForProjectHash,
        dependencies: ChatSessionsForProjectFamily._dependencies,
        allTransitiveDependencies:
            ChatSessionsForProjectFamily._allTransitiveDependencies,
        projectId: projectId,
      );

  ChatSessionsForProjectProvider._internal(
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
  Override overrideWith(
    Stream<List<ChatSession>> Function(ChatSessionsForProjectRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ChatSessionsForProjectProvider._internal(
        (ref) => create(ref as ChatSessionsForProjectRef),
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
  StreamProviderElement<List<ChatSession>> createElement() {
    return _ChatSessionsForProjectProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatSessionsForProjectProvider &&
        other.projectId == projectId;
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
mixin ChatSessionsForProjectRef on StreamProviderRef<List<ChatSession>> {
  /// The parameter `projectId` of this provider.
  int get projectId;
}

class _ChatSessionsForProjectProviderElement
    extends StreamProviderElement<List<ChatSession>>
    with ChatSessionsForProjectRef {
  _ChatSessionsForProjectProviderElement(super.provider);

  @override
  int get projectId => (origin as ChatSessionsForProjectProvider).projectId;
}

String _$chatMessagesForSessionHash() =>
    r'eb651f434b0f39e07f7c31f95a52fd1c3f83b793';

/// Reactive messages for a coordinator chat session.
///
/// Copied from [chatMessagesForSession].
@ProviderFor(chatMessagesForSession)
const chatMessagesForSessionProvider = ChatMessagesForSessionFamily();

/// Reactive messages for a coordinator chat session.
///
/// Copied from [chatMessagesForSession].
class ChatMessagesForSessionFamily
    extends Family<AsyncValue<List<ChatMessage>>> {
  /// Reactive messages for a coordinator chat session.
  ///
  /// Copied from [chatMessagesForSession].
  const ChatMessagesForSessionFamily();

  /// Reactive messages for a coordinator chat session.
  ///
  /// Copied from [chatMessagesForSession].
  ChatMessagesForSessionProvider call(int sessionId) {
    return ChatMessagesForSessionProvider(sessionId);
  }

  @override
  ChatMessagesForSessionProvider getProviderOverride(
    covariant ChatMessagesForSessionProvider provider,
  ) {
    return call(provider.sessionId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'chatMessagesForSessionProvider';
}

/// Reactive messages for a coordinator chat session.
///
/// Copied from [chatMessagesForSession].
class ChatMessagesForSessionProvider extends StreamProvider<List<ChatMessage>> {
  /// Reactive messages for a coordinator chat session.
  ///
  /// Copied from [chatMessagesForSession].
  ChatMessagesForSessionProvider(int sessionId)
    : this._internal(
        (ref) =>
            chatMessagesForSession(ref as ChatMessagesForSessionRef, sessionId),
        from: chatMessagesForSessionProvider,
        name: r'chatMessagesForSessionProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$chatMessagesForSessionHash,
        dependencies: ChatMessagesForSessionFamily._dependencies,
        allTransitiveDependencies:
            ChatMessagesForSessionFamily._allTransitiveDependencies,
        sessionId: sessionId,
      );

  ChatMessagesForSessionProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.sessionId,
  }) : super.internal();

  final int sessionId;

  @override
  Override overrideWith(
    Stream<List<ChatMessage>> Function(ChatMessagesForSessionRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ChatMessagesForSessionProvider._internal(
        (ref) => create(ref as ChatMessagesForSessionRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        sessionId: sessionId,
      ),
    );
  }

  @override
  StreamProviderElement<List<ChatMessage>> createElement() {
    return _ChatMessagesForSessionProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessagesForSessionProvider &&
        other.sessionId == sessionId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, sessionId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ChatMessagesForSessionRef on StreamProviderRef<List<ChatMessage>> {
  /// The parameter `sessionId` of this provider.
  int get sessionId;
}

class _ChatMessagesForSessionProviderElement
    extends StreamProviderElement<List<ChatMessage>>
    with ChatMessagesForSessionRef {
  _ChatMessagesForSessionProviderElement(super.provider);

  @override
  int get sessionId => (origin as ChatMessagesForSessionProvider).sessionId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
