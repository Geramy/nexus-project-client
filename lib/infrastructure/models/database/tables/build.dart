// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';
import 'project.dart';

/// Placeholder for Builds & CI runs, client + project scoped.
/// (Not yet registered in the @DriftDatabase table list — kept consistent with
/// the integer-PK convention for when it is wired up.)
class Builds extends Table {
  IntColumn get build_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();
  IntColumn get project_fk =>
      integer().nullable().references(Projects, #project_pk)();

  TextColumn get name => text()();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, running, success, failed
  TextColumn get triggeredBy => text().nullable()(); // agent or user

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
}
