// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

/// A configurable project-setup interview definition, keyed by project type +
/// (optional) sub-category. Holds the SetupFlowDefinition as JSON so the staged
/// interview is editable in the DB. Seeded from the built-in catalog; a null
/// [subCategory] is the type-generic default.
class SetupFlows extends Table {
  IntColumn get setup_flow_pk => integer().autoIncrement()();
  TextColumn get projectType => text()();
  TextColumn get subCategory => text().nullable()();

  /// Serialized SetupFlowDefinition.toJson().
  TextColumn get json => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {projectType, subCategory}
      ];
}
