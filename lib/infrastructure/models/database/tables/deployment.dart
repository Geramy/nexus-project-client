// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';
import 'project.dart';

/// Placeholder table for Deployments & Previews. Client + (optional) Project scoped.
class Deployments extends Table {
  IntColumn get deployment_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();
  IntColumn get project_fk =>
      integer().nullable().references(Projects, #project_pk)();

  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get environment => text().withDefault(const Constant('staging'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  TextColumn get triggeredBy =>
      text().nullable()(); // user or agent persona (polymorphic label)

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
}
