// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';

/// Inference Servers (AI Providers) table - client-scoped for multi-tenancy.
class InferenceServers extends Table {
  IntColumn get server_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();

  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get baseUrl => text()();
  TextColumn get apiKey => text().withDefault(const Constant(''))();
  TextColumn get providerType => text().withDefault(
    const Constant('custom'),
  )(); // lemonade, openai, ollama, etc.

  IntColumn get maxConcurrency => integer().withDefault(const Constant(4))();
  IntColumn get maxAgents => integer().withDefault(const Constant(8))();

  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get selectedModel => text().nullable()();

  // Stored as JSON string for simplicity (availableModels + extraConfig + discovered API capabilities)
  TextColumn get availableModelsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get extraConfigJson => text().withDefault(const Constant('{}'))();
  TextColumn get capabilitiesJson => text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
