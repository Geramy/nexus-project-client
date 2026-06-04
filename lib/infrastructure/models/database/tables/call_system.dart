// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'project.dart';

/// One row per IVR/Call-Systems project, holding the portable CallSystemProject
/// as JSON (the flow graph + PBX entities + prompts + variables). Kept as a JSON
/// blob — not normalized tables — because the model IS the portable export
/// contract; the builder edits it whole and exporters/runtime read it whole.
class CallSystems extends Table {
  IntColumn get call_system_pk => integer().autoIncrement()();
  IntColumn get project_fk => integer().references(Projects, #project_pk)();

  /// Serialized CallSystemProject.toJson().
  TextColumn get json => text().withDefault(const Constant('{}'))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// One call-system document per project.
  @override
  List<Set<Column>> get uniqueKeys => [
    {project_fk},
  ];
}
