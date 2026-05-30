// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';

/// Skills (capabilities) as first-class reusable Prefabs.
class Skills extends Table {
  IntColumn get skill_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)(); // Owner / publisher of the prefab

  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable()();

  /// The category this skill belongs to (e.g. "git", "build", "deploy", "filesystem", "web").
  TextColumn get category => text().withDefault(const Constant('general'))();

  /// Risk / blast radius level. Used for policy enforcement.
  TextColumn get riskLevel => text().withDefault(const Constant('medium'))(); // low, medium, high, critical

  /// Default permission when this skill is granted via a Persona.
  TextColumn get defaultPermission => text().withDefault(const Constant('ask'))(); // grant, ask, deny

  // Rich configuration (allowed paths, dangerous commands, etc.)
  TextColumn get configJson => text().withDefault(const Constant('{}'))();

  // ==================== Prefab System ====================
  BoolColumn get isPrefab => boolean().withDefault(const Constant(false))();
  IntColumn get prefab_fk => integer().nullable().references(Skills, #skill_pk)();
  TextColumn get overridesJson => text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
