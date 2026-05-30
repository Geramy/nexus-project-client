// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'ci_job.dart';

/// One step within a [CiJobs] job (a GitHub Actions step). Holds the command it
/// ran (a `run:` script or a `uses:` reference), its exit code, and the captured
/// log output appended as the step executes.
class CiSteps extends Table {
  IntColumn get ci_step_pk => integer().autoIncrement()();
  IntColumn get ci_job_fk => integer().references(CiJobs, #ci_job_pk)();

  TextColumn get name => text().withLength(min: 1, max: 250)();

  /// pending | running | success | failed | cancelled | skipped
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  /// The shell script (`run:`) or action reference (`uses:`) this step executes.
  TextColumn get command => text().nullable()();

  IntColumn get exitCode => integer().nullable()();

  /// Captured stdout+stderr, appended line-by-line as the step runs.
  TextColumn get logText => text().withDefault(const Constant(''))();

  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}
