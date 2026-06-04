// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

/// A node in the project-setup scoping tree. A scope specializes the setup
/// interview: picking an industry (axis `industry`, e.g. "Gaming") can introduce
/// a sub-axis (e.g. "Genre"), whose values are themselves child scopes
/// (axis `genre`, value "RPG", parent = the Gaming scope). Each scope owns a set
/// of [SetupScopeOptions] that re-scope the downstream objectives/features/
/// libraries (and platform-conditional language/framework stacks).
class SetupScopes extends Table {
  IntColumn get setup_scope_pk => integer().autoIncrement()();

  /// The dimension this scope value lives on: `industry`, or a sub-axis key
  /// such as `genre`, `segment`, `business-model`, …
  TextColumn get axis => text()();

  /// The scope value, e.g. "Gaming", "RPG".
  TextColumn get value => text()();

  /// Parent scope (e.g. genre "RPG"'s parent is industry "Gaming"). Null for
  /// top-level (industry) scopes.
  IntColumn get parent_scope_fk =>
      integer().nullable().references(SetupScopes, #setup_scope_pk)();

  /// If this scope introduces a further sub-axis, its display name (e.g.
  /// "Genre"); null when the scope has no sub-axis.
  TextColumn get subAxisName => text().nullable()();

  /// The lowercase slug/category key for the introduced sub-axis (e.g. "genre").
  TextColumn get subAxisKey => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {axis, value, parent_scope_fk},
  ];
}
