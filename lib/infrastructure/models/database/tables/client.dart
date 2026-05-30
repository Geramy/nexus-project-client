// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

/// Clients table - top level of the hierarchy (Default client + user-created ones)
class Clients extends Table {
  IntColumn get client_pk => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
