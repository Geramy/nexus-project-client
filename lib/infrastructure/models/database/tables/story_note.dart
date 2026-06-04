// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'user_story.dart';

/// Free-form descriptive notes attached to a user story (Exploration phase).
/// Each note is individually addressable (note_pk) so the Coordinator can
/// add/update/delete/get them, and the UI shows them as clickable "pills".
class StoryNotes extends Table {
  IntColumn get note_pk => integer().autoIncrement()();

  IntColumn get story_fk => integer().references(UserStories, #story_pk)();

  /// The note text.
  TextColumn get body => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
