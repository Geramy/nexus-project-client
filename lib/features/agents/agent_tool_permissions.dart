// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

/// Tool-safety permission model for agents.
///
/// Every coordinator tool has a permission level per agent:
///   - [grant] : the agent may call the tool freely.
///   - [ask]   : a human must approve each call (chat shows a confirm dialog).
///   - [deny]  : the tool is blocked for this agent.
///
/// Defaults live in [kCoordinatorToolSpecs]; per-agent overrides are stored in
/// the persona's `configJson` under `toolPermissions: { <tool>: "grant|ask|deny" }`.
enum ToolPerm { grant, ask, deny }

ToolPerm toolPermFromString(String? s) {
  switch (s) {
    case 'deny':
      return ToolPerm.deny;
    case 'ask':
      return ToolPerm.ask;
    case 'grant':
      return ToolPerm.grant;
    default:
      return ToolPerm.grant;
  }
}

String toolPermToString(ToolPerm p) => p.name;

/// One row in the tool catalog: the wire name, a UI group + label, and the
/// default permission when the agent hasn't overridden it.
class ToolSpec {
  final String name;
  final String category;
  final String label;
  final ToolPerm defaultPerm;
  final bool destructive;
  const ToolSpec(
    this.name,
    this.category,
    this.label,
    this.defaultPerm, {
    this.destructive = false,
  });
}

/// Single source of truth for the coordinator's tools (keep in sync with
/// CoordinatorTools.buildToolSchemas). Destructive ops default to [ask].
const List<ToolSpec> kCoordinatorToolSpecs = [
  // Tasks
  ToolSpec('list_tasks', 'Tasks', 'List tasks', ToolPerm.grant),
  ToolSpec('list_open_tasks', 'Tasks', 'List open tasks', ToolPerm.grant),
  ToolSpec('get_task', 'Tasks', 'Read task details', ToolPerm.grant),
  ToolSpec('create_task', 'Tasks', 'Create task / subtask', ToolPerm.grant),
  ToolSpec('update_task', 'Tasks', 'Edit task', ToolPerm.grant),
  ToolSpec('update_task_status', 'Tasks', 'Change task status', ToolPerm.grant),
  ToolSpec('set_task_dates', 'Tasks', 'Set task dates', ToolPerm.grant),
  ToolSpec(
    'set_task_build_config',
    'Tasks',
    'Configure task build gate',
    ToolPerm.grant,
  ),
  ToolSpec('link_task_to_plan', 'Tasks', 'Link task to plan', ToolPerm.grant),
  ToolSpec(
    'delete_task',
    'Tasks',
    'Delete task',
    ToolPerm.ask,
    destructive: true,
  ),
  // Agents
  ToolSpec('list_agents', 'Agents', 'List agents', ToolPerm.grant),
  ToolSpec(
    'assign_agent_to_task',
    'Agents',
    'Assign agent to task',
    ToolPerm.grant,
  ),
  // Plans
  ToolSpec('list_plans', 'Plans', 'List plans', ToolPerm.grant),
  ToolSpec('view_current_plan', 'Plans', 'View current plan', ToolPerm.grant),
  ToolSpec('view_plan', 'Plans', 'View open plan', ToolPerm.grant),
  ToolSpec('read_plan', 'Plans', 'Read plan', ToolPerm.grant),
  ToolSpec('create_plan', 'Plans', 'Create plan / folder', ToolPerm.grant),
  ToolSpec('update_plan', 'Plans', 'Update open plan', ToolPerm.grant),
  ToolSpec('write_plan', 'Plans', 'Write plan', ToolPerm.grant),
  ToolSpec('rename_plan', 'Plans', 'Rename plan', ToolPerm.grant),
  ToolSpec(
    'delete_plan',
    'Plans',
    'Delete plan / folder',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'propose_plan_adjustment',
    'Plans',
    'Propose plan adjustment',
    ToolPerm.grant,
  ),
  ToolSpec(
    'sync_plans_to_tasks',
    'Plans',
    'Sync plans → tasks',
    ToolPerm.grant,
  ),
  // Files
  ToolSpec('list_files', 'Files', 'List workspace files', ToolPerm.grant),
  ToolSpec('read_file', 'Files', 'Read file', ToolPerm.grant),
  ToolSpec(
    'write_file',
    'Files',
    'Create / overwrite file',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec('create_directory', 'Files', 'Create directory', ToolPerm.grant),
  ToolSpec(
    'move_path',
    'Files',
    'Move / rename file',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'delete_path',
    'Files',
    'Delete file / folder',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'delete_file',
    'Files',
    'Delete file',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'delete_folder',
    'Files',
    'Delete folder',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec('list_directory', 'Files', 'List directory', ToolPerm.grant),
  ToolSpec(
    'search_directory',
    'Files',
    'Search directory contents',
    ToolPerm.grant,
  ),
  ToolSpec(
    'search_file_content',
    'Files',
    'Search within a file',
    ToolPerm.grant,
  ),
  ToolSpec('read_file_chunk', 'Files', 'Read file line range', ToolPerm.grant),
  ToolSpec(
    'create_file',
    'Files',
    'Create new file',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'edit_file',
    'Files',
    'Edit file (replace text)',
    ToolPerm.ask,
    destructive: true,
  ),
  // Git
  ToolSpec('git_status', 'Git', 'Git status', ToolPerm.grant),
  ToolSpec('git_log', 'Git', 'Git log', ToolPerm.grant),
  ToolSpec(
    'git_commit',
    'Git',
    'Commit changes',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec('git_branches', 'Git', 'List branches', ToolPerm.grant),
  ToolSpec('git_create_branch', 'Git', 'Create branch', ToolPerm.grant),
  ToolSpec(
    'git_checkout_branch',
    'Git',
    'Switch branch',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'git_push',
    'Git',
    'Push to remote',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'git_pull',
    'Git',
    'Pull from remote',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec('git_merge', 'Git', 'Merge branch', ToolPerm.ask, destructive: true),
  // User stories (post-setup Exploration / discovery)
  ToolSpec('add_user_story', 'Stories', 'Add a user story', ToolPerm.grant),
  ToolSpec(
    'update_user_story',
    'Stories',
    'Update a user story',
    ToolPerm.grant,
  ),
  ToolSpec('list_user_stories', 'Stories', 'List user stories', ToolPerm.grant),
  // Build / CI
  ToolSpec(
    'build_docker_image',
    'Build',
    'Build Docker image',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'run_workflow',
    'Build',
    'Run CI workflow',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'scaffold_ci_workflow',
    'Build',
    'Scaffold default CI workflow',
    ToolPerm.grant,
  ),
  ToolSpec('list_ci_runs', 'Build', 'List build / CI runs', ToolPerm.grant),
  ToolSpec('get_ci_run', 'Build', 'Read build / CI run', ToolPerm.grant),
  // Orchestration (spawn → submit → verify → review loop). Names mirror the
  // consts in agent_role_policy.dart (kept as literals to avoid an import cycle).
  ToolSpec(
    'submit_for_completion',
    'Orchestration',
    'Submit task for completion',
    ToolPerm.grant,
  ),
  ToolSpec(
    'run_verification',
    'Orchestration',
    'Run task verification',
    ToolPerm.grant,
  ),
  ToolSpec(
    'submit_verdict',
    'Orchestration',
    'Emit pass/fail verdict',
    ToolPerm.grant,
  ),
  ToolSpec(
    'review_submission',
    'Orchestration',
    'Review a submission',
    ToolPerm.grant,
  ),
  ToolSpec(
    'approve_task',
    'Orchestration',
    'Approve & integrate task',
    ToolPerm.ask,
    destructive: true,
  ),
  ToolSpec(
    'reject_task',
    'Orchestration',
    'Send task back to board',
    ToolPerm.grant,
  ),
  // Other
  ToolSpec(
    'generate_diagram',
    'Other',
    'Generate diagram (image)',
    ToolPerm.grant,
  ),
];

ToolSpec? toolSpecFor(String name) {
  for (final t in kCoordinatorToolSpecs) {
    if (t.name == name) return t;
  }
  return null;
}

/// Ordered list of categories for grouped UI rendering.
List<String> get kToolCategories {
  final seen = <String>[];
  for (final t in kCoordinatorToolSpecs) {
    if (!seen.contains(t.category)) seen.add(t.category);
  }
  return seen;
}

/// Resolves effective tool permissions for an agent: defaults merged with the
/// per-agent overrides parsed from `configJson`.
class AgentToolPermissions {
  final Map<String, ToolPerm> overrides;
  const AgentToolPermissions(this.overrides);

  static const AgentToolPermissions allDefaults = AgentToolPermissions({});

  factory AgentToolPermissions.fromConfigJson(String? configJson) {
    final map = <String, ToolPerm>{};
    if (configJson != null && configJson.trim().isNotEmpty) {
      try {
        final cfg = jsonDecode(configJson);
        if (cfg is Map && cfg['toolPermissions'] is Map) {
          (cfg['toolPermissions'] as Map).forEach((k, v) {
            map['$k'] = toolPermFromString('$v');
          });
        }
      } catch (_) {}
    }
    return AgentToolPermissions(map);
  }

  /// Effective permission for [tool]: explicit override, else catalog default,
  /// else grant (unknown tools).
  ToolPerm permFor(String tool) {
    if (overrides.containsKey(tool)) return overrides[tool]!;
    return toolSpecFor(tool)?.defaultPerm ?? ToolPerm.grant;
  }

  /// Merge these tool permissions into an existing configJson, preserving other
  /// keys. Returns the new JSON string.
  static String writeIntoConfigJson(
    String? configJson,
    Map<String, ToolPerm> perms,
  ) {
    Map<String, dynamic> cfg = {};
    if (configJson != null && configJson.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(configJson);
        if (parsed is Map) cfg = Map<String, dynamic>.from(parsed);
      } catch (_) {}
    }
    cfg['toolPermissions'] = {
      for (final e in perms.entries) e.key: toolPermToString(e.value),
    };
    return jsonEncode(cfg);
  }
}
