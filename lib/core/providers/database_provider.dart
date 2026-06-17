// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';

// NOTE: These are hand-written providers (not riverpod_generator codegen).
// riverpod_generator 4 cannot resolve Drift's `part`-generated row types
// (Client/Project/Task/… live in nexus_database.g.dart) during its build phase,
// so generating providers that RETURN those types throws InvalidTypeException.
// Declaring them manually sidesteps codegen entirely while keeping the exact
// same provider names, types, call syntax, and keep-alive (non-autoDispose)
// semantics the rest of the app already uses.

/// Global Drift database instance (singleton).
/// All reactive queries for Clients, Projects, and Tasks should come from here.
NexusDatabase? _dbInstance;

final nexusDatabaseProvider = Provider<NexusDatabase>((ref) {
  if (_dbInstance != null) return _dbInstance!;
  final db = NexusDatabase();
  _dbInstance = db;
  ref.onDispose(() {
    _dbInstance?.close();
    _dbInstance = null;
  });
  return db;
});

/// Reactive list of all clients (updates automatically on any change)
final allClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(nexusDatabaseProvider).watchAllClients();
});

/// Reactive list of projects for a specific client
final projectsForClientProvider =
    StreamProvider.family<List<Project>, int>((ref, clientId) {
  return ref.watch(nexusDatabaseProvider).watchProjectsForClient(clientId);
});

/// Reactive all tasks for a project (flat list, good for building trees client-side)
final allTasksForProjectProvider =
    StreamProvider.family<List<Task>, int>((ref, projectId) {
  return ref.watch(nexusDatabaseProvider).watchTasksForProject(projectId);
});

/// Reactive list of Inference Servers for the current Client (multi-tenancy)
final inferenceServersForClientProvider =
    StreamProvider.family<List<InferenceServer>, int>((ref, clientId) {
  return ref.watch(nexusDatabaseProvider).watchInferenceServersForClient(clientId);
});

/// Reactive list of Agent Personas for the current Client (multi-tenancy)
final agentPersonasForClientProvider =
    StreamProvider.family<List<AgentPersona>, int>((ref, clientId) {
  return ref.watch(nexusDatabaseProvider).watchAgentPersonasForClient(clientId);
});

/// Reactive Deployments for client (Phase 1 placeholder)
final deploymentsForClientProvider =
    StreamProvider.family<List<Deployment>, int>((ref, clientId) {
  return ref.watch(nexusDatabaseProvider).watchDeploymentsForClient(clientId);
});

/// Reactive Activity Logs for client (Phase 1 placeholder)
final activityLogsForClientProvider =
    StreamProvider.family<List<ActivityLog>, int>((ref, clientId) {
  return ref.watch(nexusDatabaseProvider).watchActivityLogsForClient(clientId);
});

/// Reactive CI Runs for client (Phase 1 placeholder)
final ciRunsForClientProvider =
    StreamProvider.family<List<CiRun>, int>((ref, clientId) {
  return ref.watch(nexusDatabaseProvider).watchCiRunsForClient(clientId);
});

/// Reactive Coordinator chat sessions for a project (Client → Project → Session).
final chatSessionsForProjectProvider =
    StreamProvider.family<List<ChatSession>, int>((ref, projectId) {
  return ref.watch(nexusDatabaseProvider).watchChatSessionsForProject(projectId);
});

/// Reactive messages for a coordinator chat session.
final chatMessagesForSessionProvider =
    StreamProvider.family<List<ChatMessage>, int>((ref, sessionId) {
  return ref.watch(nexusDatabaseProvider).watchChatMessagesForSession(sessionId);
});

/// App-wide stream of task-completion events (a task was approved → Done). The
/// main shell listens to this to show a tappable "task complete" notification.
final taskCompletedStreamProvider = StreamProvider<TaskCompletedEvent>((ref) {
  return ref.watch(nexusDatabaseProvider).taskCompleted;
});
