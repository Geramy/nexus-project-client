// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart';

import 'client.dart';
import 'inference_server.dart';

/// Agent Personas table - client-scoped for proper multi-tenancy.
///
/// Supports **Prefabs**:
/// - Rows where `isPrefab = true` are reusable templates (source of truth).
/// - Rows with `prefab_fk` set are **instances** that inherit from a prefab.
/// - `overridesJson` stores local modifications that take precedence over the prefab.
class AgentPersonas extends Table {
  IntColumn get agent_pk => integer().autoIncrement()();
  IntColumn get client_fk => integer().references(Clients, #client_pk)();

  TextColumn get name => text().withLength(min: 1, max: 100)();
  /// Human-readable job title / role (e.g. "Backend Engineer", "QA Lead").
  /// Surfaced to the orchestrator so it can pick the right agent for a task.
  TextColumn get title => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get primaryModel => text().nullable()();

  RealColumn get costPerMillionTokens => real().withDefault(const Constant(0.0))();

  // Stored as JSON for flexibility (capabilities list, blast radius rules, etc.)
  TextColumn get capabilitiesJson => text().withDefault(const Constant('[]'))();
  TextColumn get configJson => text().withDefault(const Constant('{}'))(); // permissions, approval gates, etc.

  // ==================== Prefab System ====================
  /// Whether this Persona is a reusable Prefab (template).
  BoolColumn get isPrefab => boolean().withDefault(const Constant(false))();

  /// If set, this Persona is an *instance* that derives from the referenced Prefab.
  IntColumn get prefab_fk => integer().nullable().references(AgentPersonas, #agent_pk)();

  /// JSON map of fields that have been customized locally on this instance.
  TextColumn get overridesJson => text().withDefault(const Constant('{}'))();

  // ==================== AI Provider Selection (global list) ====================
  /// References a row in the InferenceServers table (the global "AI Providers" list).
  IntColumn get provider_fk => integer().nullable().references(InferenceServers, #server_pk)();

  // ==================== Omni Collection + Modality Routing ====================
  TextColumn get omniCollectionModel => text().nullable()();
  TextColumn get ttsModel => text().nullable()();        // Text → Voice
  TextColumn get sttModel => text().nullable()();        // Voice → Text
  TextColumn get imageGenModel => text().nullable()();   // Image generation
  TextColumn get visionModel => text().nullable()();     // Image reading / understanding
  TextColumn get llmModel => text().nullable()();        // Text generation (primary LLM)

  /// Kokoro TTS voice id (e.g. 'af_heart', 'am_michael'). Null = default voice.
  TextColumn get ttsVoice => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
