// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'chat_session.dart';

/// A single message within a Coordinator [ChatSessions] conversation.
class ChatMessages extends Table {
  IntColumn get message_pk => integer().autoIncrement()();
  IntColumn get session_fk => integer().references(ChatSessions, #session_pk)();

  /// 'user' | 'assistant' | 'system'
  TextColumn get role => text()();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// Retained path to synthesized TTS audio for assistant voice replies.
  TextColumn get audioPath => text().nullable()();

  /// Monotonic ordering key within the session (millisecondsSinceEpoch at insert).
  IntColumn get seq => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
