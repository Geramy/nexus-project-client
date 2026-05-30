// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';
import 'project.dart';

/// Placeholder table for Activity / Audit events. Client + (optional) Project scoped.
class ActivityLogs extends Table {
  IntColumn get activity_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();
  IntColumn get project_fk => integer().nullable().references(Projects, #project_pk)();

  TextColumn get actorType => text().withDefault(const Constant('user'))(); // user, agent, system
  TextColumn get actorId => text().nullable()(); // polymorphic actor reference

  TextColumn get action => text()(); // e.g. "task.created", "build.started"
  TextColumn get targetType => text().nullable()();
  TextColumn get targetId => text().nullable()();

  TextColumn get summary => text().nullable()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
