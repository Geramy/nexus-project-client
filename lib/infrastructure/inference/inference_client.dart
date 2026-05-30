// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Backward-compatibility layer for the old `InferenceClient` API.
///
/// All types are re-exported from inference_backend.dart so existing imports:
///   import 'package:nexus_projects_client/infrastructure/inference/inference_client.dart';
/// continue to work without changes in coordinator_session, coordinator_chat_screen,
/// coordinator_tools, tts_service, and coordinator_voice_session.
///
/// The old `InferenceClient` class has been replaced by the abstract
/// [InferenceBackend] interface + concrete implementations (LemonadeBackend, etc.).
/// This file provides type aliases so legacy code compiles cleanly during migration.

import 'inference_backend.dart';
export 'inference_backend.dart';

// ── Type Aliases for Backward Compatibility ────────────────────────

/// Old name: `InferenceClient`. Now an alias to the abstract interface.
/// Concrete instances are created via [LemonadeBackend] or factory methods.
typedef InferenceClient = InferenceBackend;
