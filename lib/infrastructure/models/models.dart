// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// Barrel file for all models under infrastructure/models.
//
// Structure:
//   ui/        → Plain UI / domain model classes (Task, Project, AgentPersona, InferenceServer)
//   database/  → Drift table definitions (schema only)

export 'ui/task.dart';
export 'ui/project.dart';
export 'ui/agent_persona.dart';
export 'ui/inference_server.dart';
export 'ui/persona_diff.dart';

// Database / Drift models (tables)
export 'database/tables/client.dart';
export 'database/tables/project.dart';
export 'database/tables/task.dart';
export 'database/tables/inference_server.dart';
export 'database/tables/agent_persona.dart';
export 'database/tables/skill.dart';
export 'database/tables/deployment.dart';
export 'database/tables/activity_log.dart';
export 'database/tables/ci_run.dart';
