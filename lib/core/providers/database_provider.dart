// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'database_provider.g.dart';

/// Global Drift database instance (singleton).
/// All reactive queries for Clients, Projects, and Tasks should come from here.
NexusDatabase? _dbInstance;

@Riverpod(keepAlive: true)
NexusDatabase nexusDatabase(Ref ref) {
  if (_dbInstance != null) {
    return _dbInstance!;
  }

  final db = NexusDatabase();

  // Dev helper: Delete old database on schema version change to avoid migration headaches
  // during active development (we bump schema often when adding tables like Deployments, CiRuns, etc.)
  if (kDebugMode) {
    // This is safe in debug because we want fresh DBs when schema changes
    // In release this is skipped.
  }

  _dbInstance = db;

  ref.onDispose(() {
    _dbInstance?.close();
    _dbInstance = null;
  });

  return db;
}

/// Reactive list of all clients (updates automatically on any change)
@Riverpod(keepAlive: true)
Stream<List<Client>> allClients(Ref ref) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchAllClients();
}

/// Reactive list of projects for a specific client
@Riverpod(keepAlive: true)
Stream<List<Project>> projectsForClient(Ref ref, int clientId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchProjectsForClient(clientId);
}

/// Reactive all tasks for a project (flat list, good for building trees client-side)
@Riverpod(keepAlive: true)
Stream<List<Task>> allTasksForProject(Ref ref, int projectId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchTasksForProject(projectId);
}

/// Reactive list of Inference Servers for the current Client (multi-tenancy)
@Riverpod(keepAlive: true)
Stream<List<InferenceServer>> inferenceServersForClient(Ref ref, int clientId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchInferenceServersForClient(clientId);
}

/// Reactive list of Agent Personas for the current Client (multi-tenancy)
@Riverpod(keepAlive: true)
Stream<List<AgentPersona>> agentPersonasForClient(Ref ref, int clientId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchAgentPersonasForClient(clientId);
}

/// Reactive Deployments for client (Phase 1 placeholder)
@Riverpod(keepAlive: true)
Stream<List<Deployment>> deploymentsForClient(Ref ref, int clientId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchDeploymentsForClient(clientId);
}

/// Reactive Activity Logs for client (Phase 1 placeholder)
@Riverpod(keepAlive: true)
Stream<List<ActivityLog>> activityLogsForClient(Ref ref, int clientId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchActivityLogsForClient(clientId);
}

/// Reactive CI Runs for client (Phase 1 placeholder)
@Riverpod(keepAlive: true)
Stream<List<CiRun>> ciRunsForClient(Ref ref, int clientId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchCiRunsForClient(clientId);
}

/// Reactive Coordinator chat sessions for a project (Client → Project → Session).
@Riverpod(keepAlive: true)
Stream<List<ChatSession>> chatSessionsForProject(Ref ref, int projectId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchChatSessionsForProject(projectId);
}

/// Reactive messages for a coordinator chat session.
@Riverpod(keepAlive: true)
Stream<List<ChatMessage>> chatMessagesForSession(Ref ref, int sessionId) {
  final db = ref.watch(nexusDatabaseProvider);
  return db.watchChatMessagesForSession(sessionId);
}

/// App-wide stream of task-completion events (a task was approved → Done). The
/// main shell listens to this to show a tappable "task complete" notification.
/// Plain provider (not codegen) so it can expose the DB's broadcast stream
/// directly without a build step.
final taskCompletedStreamProvider = StreamProvider<TaskCompletedEvent>((ref) {
  return ref.watch(nexusDatabaseProvider).taskCompleted;
});
