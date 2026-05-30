// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'ci_run.dart';

/// One job within a [CiRuns] run (a GitHub Actions `jobs:` entry). Jobs within a
/// run may run sequentially; each has an ordered list of CiSteps.
class CiJobs extends Table {
  IntColumn get ci_job_pk => integer().autoIncrement()();
  IntColumn get ci_run_fk => integer().references(CiRuns, #ci_run_pk)();

  TextColumn get name => text().withLength(min: 1, max: 150)();

  /// pending | running | success | failed | cancelled | skipped
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// The workflow's `runs-on` value (e.g. `ubuntu-latest`) → the container image
  /// the local runner uses. Null for a plain Docker build job.
  TextColumn get runsOn => text().nullable()();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}
