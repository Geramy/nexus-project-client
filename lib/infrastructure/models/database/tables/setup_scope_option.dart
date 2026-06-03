// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'setup_scope.dart';

/// One scoped vocabulary entry belonging to a [SetupScopes] node. This single
/// table carries BOTH plain scoped suggestions (objectives/features with a null
/// [platform]) AND platform-conditional stack entries (languages/frameworks/
/// libraries tagged with the [platform] they apply to — e.g. desktop games use
/// C#/C++ engines while mobile games use Flutter/Flame).
class SetupScopeOptions extends Table {
  IntColumn get setup_scope_option_pk => integer().autoIncrement()();

  IntColumn get setup_scope_fk =>
      integer().references(SetupScopes, #setup_scope_pk)();

  /// Which setup category this option feeds: `objectives`, `features`,
  /// `platforms`, `languages`, `frameworks`, `libraries`.
  TextColumn get category => text()();

  TextColumn get value => text()();

  /// For platform-conditional stack entries (languages/frameworks/libraries):
  /// the platform this entry applies to (`Mobile`, `Desktop`, `Web`, `Console`,
  /// `Embedded`, `Cloud/Server`). Null for platform-agnostic suggestions.
  TextColumn get platform => text().nullable()();

  /// Libraries only: the language/ecosystem the package belongs to (e.g. "Dart",
  /// "C#", "C++"). Null for non-library entries.
  TextColumn get forLanguage => text().nullable()();

  IntColumn get sort => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {setup_scope_fk, category, platform, value}
      ];
}
