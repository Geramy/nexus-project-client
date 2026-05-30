// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'project.dart';

/// Structured project profile tags emitted during Project Setup (and kept in
/// sync afterward). The unifying data model for the setup workflow: every
/// language / framework / library / platform / objective / industry decision is
/// a row here, with provenance and a confirm state.
///
/// Status semantics: `proposed` = active-but-unconfirmed (stays unless the user
/// rejects it), `accepted` = confirmed (✓), `rejected` = struck out (✗).
/// Downstream consumers read everything EXCEPT `rejected`.
class ProjectTags extends Table {
  IntColumn get tag_pk => integer().autoIncrement()();
  IntColumn get project_fk => integer().references(Projects, #project_pk)();

  /// One of: industries | platforms | objectives | languages | frameworks | libraries.
  TextColumn get category => text()();
  TextColumn get value => text()();

  /// Who introduced the tag: user | ai | workspace (observed from real files).
  TextColumn get source => text().withDefault(const Constant('ai'))();

  /// Where it came from: setup | plan | agent | workspace.
  TextColumn get origin => text().withDefault(const Constant('setup'))();

  /// Confirm state: proposed | accepted | rejected.
  TextColumn get status => text().withDefault(const Constant('proposed'))();

  /// Which architecture layer this tag belongs to: client | server | db |
  /// worker | module. Null = project-wide (industries, cross-cutting objectives).
  TextColumn get layerKey => text().nullable()();

  /// For library tags: the language this library is used with (e.g. a Dart
  /// package vs. a C# NuGet). Must be one of the closed Languages vocab.
  /// Null for non-library tags (or libraries not yet attached to a language).
  TextColumn get forLanguage => text().nullable()();

  /// Short explanation of why the AI proposed this tag.
  TextColumn get rationale => text().nullable()();

  /// For library/framework tags: the canonical source (GitHub repo / pub.dev).
  TextColumn get sourceUrl => text().nullable()();

  /// Freshness verdict snapshot for library/framework tags: fresh|aging|stale|dead.
  TextColumn get verdict => text().nullable()();
  DateTimeColumn get verifiedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
