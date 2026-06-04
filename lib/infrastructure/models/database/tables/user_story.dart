// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'project.dart';

/// User stories captured during the post-setup **Project Exploration** phase —
/// the discovery interview where the Coordinator fleshes the idea out BEFORE any
/// tasks are generated. Stories form a tree (epics → stories → sub-stories) via
/// [parent_story_fk], and are rendered as a UML-style node/edge diagram. Tasks
/// later link back to the story item they implement (Tasks.task_story_fk), so the
/// system can trace any task to its originating story and vice-versa.
class UserStories extends Table {
  IntColumn get story_pk => integer().autoIncrement()();

  IntColumn get project_fk => integer().references(Projects, #project_pk)();

  /// Tree edge: the parent story (epic → story → sub-story). Null = root/epic.
  IntColumn get parent_story_fk =>
      integer().nullable().references(UserStories, #story_pk)();

  /// Short node title shown on the canvas.
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// The story narrative — `As a <role>, I want <goal>, so that <benefit>`.
  TextColumn get narrative => text().withDefault(const Constant(''))();

  /// Acceptance criteria (markdown bullet list), if captured.
  TextColumn get acceptanceCriteria => text().nullable()();

  /// Node kind: epic | story | substory. Drives the canvas styling.
  TextColumn get kind => text().withDefault(const Constant('story'))();

  /// Confirm state: draft | confirmed | done.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// Persisted canvas position (null until first auto-layout / drag).
  RealColumn get posX => real().nullable()();
  RealColumn get posY => real().nullable()();

  /// Sibling order under the same parent.
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
