// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'project.dart';

/// A persisted Project Coordinator conversation, scoped to a project and —
/// when the conversation is about a specific plan document — to that plan, so
/// tasks/decisions can be backtracked to the plan and the chat that produced
/// them. [plan_path] is null for general project-level conversations; otherwise
/// it is the plan file's workspace path (e.g. `/PLANS/Roadmap.md`).
class ChatSessions extends Table {
  IntColumn get session_pk => integer().autoIncrement()();
  IntColumn get project_fk => integer().references(Projects, #project_pk)();
  TextColumn get plan_path => text().nullable()();

  TextColumn get title =>
      text().withDefault(const Constant('New conversation'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
