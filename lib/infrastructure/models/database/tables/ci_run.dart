// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';
import 'project.dart';
import 'task.dart';

/// A build / CI run, client + (optional) project scoped. Models a
/// GitHub-Actions-shaped execution: a run has one or more [CiJobs], each with an
/// ordered list of [CiSteps]. A plain Docker build is represented as a run with
/// a single job + single step, so the hierarchy is uniform.
class CiRuns extends Table {
  IntColumn get ci_run_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();
  IntColumn get project_fk => integer().nullable().references(Projects, #project_pk)();

  /// The task this run gates, if any. When set and the run succeeds the task is
  /// auto-approved (→ Done); when it fails the task returns to the board.
  IntColumn get task_fk => integer().nullable().references(Tasks, #task_pk)();

  TextColumn get name => text().withLength(min: 1, max: 150)();

  /// pending | running | success | failed | cancelled | skipped
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// dockerBuild | workflow
  TextColumn get kind => text().withDefault(const Constant('dockerBuild'))();

  /// localDocker | remote
  TextColumn get backend => text().withDefault(const Constant('localDocker'))();

  TextColumn get branch => text().nullable()();
  TextColumn get commitOid => text().nullable()();

  /// Docker build: the Dockerfile workspace path + produced image tag.
  TextColumn get dockerfilePath => text().nullable()();
  TextColumn get imageTag => text().nullable()();

  /// Workflow run: the workflow YAML workspace path.
  TextColumn get workflowPath => text().nullable()();

  TextColumn get triggeredBy => text().nullable()();

  /// Set when the run failed to start (e.g. docker not installed).
  TextColumn get errorText => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
}
