// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

/// Cached freshness check for a package/repo, keyed by (ecosystem, name). The
/// verdict is computed deterministically from release/commit dates + archived
/// state, with a TTL so we don't hammer registry APIs (GitHub's unauthenticated
/// limit is 60 req/hr) and re-opening the Tag Board is instant.
class LibraryVerifications extends Table {
  IntColumn get verification_pk => integer().autoIncrement()();

  /// pubdev | github | crates | nuget | maven | npm.
  TextColumn get ecosystem => text()();
  TextColumn get name => text()();

  TextColumn get repoUrl => text().nullable()();
  DateTimeColumn get lastCommit => dateTime().nullable()();
  DateTimeColumn get lastRelease => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// Stars (GitHub) or likes (pub.dev).
  IntColumn get popularity => integer().nullable()();

  /// GitHub owner/org, for trust-by-org (e.g. flutter, google, facebook/meta).
  TextColumn get owner => text().nullable()();

  /// fresh | aging | stale | dead.
  TextColumn get verdict => text()();
  DateTimeColumn get checkedAt => dateTime().withDefault(currentDateAndTime)();
}
