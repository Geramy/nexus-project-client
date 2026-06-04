// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

/// The editable prompt templates the orchestrator wraps around each role's
/// [defaultSystemPrompt]. The role prompt itself (the "who you are / what your
/// job is" text) is still generated from the agent's role; these templates are
/// the per-stage *framing* and *kickoff* text the orchestrator adds on top.
///
/// Each field supports placeholders that are substituted at run time:
///   {taskId} {title} {branch} {description} {acceptanceCriteria} {verification}
enum OrchestratorPromptField {
  workerFraming,
  workerKickoff,
  workerContinue,
  verifyFraming,
  verifyKickoff,
  verifyContinue,
  mergeFraming,
  mergeKickoff,
  mergeContinue,

  /// The system prompt for the post-setup Exploration (discovery) coordinator —
  /// how it interviews the user and builds the user-story TREE. Configurable
  /// here so the hierarchy behavior is a system setting, not buried in code.
  discoverySystem,
}

extension OrchestratorPromptFieldX on OrchestratorPromptField {
  /// Stable key used in the persisted JSON map.
  String get key => name;

  /// Short UI label.
  String get label => switch (this) {
    OrchestratorPromptField.workerFraming => 'Worker — task framing',
    OrchestratorPromptField.workerKickoff => 'Worker — first message',
    OrchestratorPromptField.workerContinue => 'Worker — continue message',
    OrchestratorPromptField.verifyFraming => 'Verify — task framing',
    OrchestratorPromptField.verifyKickoff => 'Verify — first message',
    OrchestratorPromptField.verifyContinue => 'Verify — continue message',
    OrchestratorPromptField.mergeFraming => 'Merge — task framing',
    OrchestratorPromptField.mergeKickoff => 'Merge — first message',
    OrchestratorPromptField.mergeContinue => 'Merge — continue message',
    OrchestratorPromptField.discoverySystem =>
      'Discovery — system prompt (user-story interview)',
  };

  /// Which pipeline stage this template belongs to (for UI grouping).
  String get stage => switch (this) {
    OrchestratorPromptField.workerFraming ||
    OrchestratorPromptField.workerKickoff ||
    OrchestratorPromptField.workerContinue => 'Implement',
    OrchestratorPromptField.verifyFraming ||
    OrchestratorPromptField.verifyKickoff ||
    OrchestratorPromptField.verifyContinue => 'Verify',
    OrchestratorPromptField.mergeFraming ||
    OrchestratorPromptField.mergeKickoff ||
    OrchestratorPromptField.mergeContinue => 'Merge',
    OrchestratorPromptField.discoverySystem => 'Exploration (user stories)',
  };

  /// True for the multi-line framing templates (rendered with a taller editor).
  bool get isMultiline => switch (this) {
    OrchestratorPromptField.workerFraming ||
    OrchestratorPromptField.verifyFraming ||
    OrchestratorPromptField.mergeFraming ||
    OrchestratorPromptField.discoverySystem => true,
    _ => false,
  };

  /// The built-in default for this template.
  String get defaultValue => _defaults[this]!;
}

const Map<OrchestratorPromptField, String> _defaults = {
  OrchestratorPromptField.workerFraming: '''
=== YOUR ASSIGNED TASK ===
Task #{taskId}: {title}
Description: {description}
Acceptance criteria (definition of done): {acceptanceCriteria}
Verification (how completion is proven): {verification}
Work branch: "{branch}" — every commit you make must land on this branch.

Implement this task end-to-end: read the relevant code first, make the changes, then commit them to your branch with git_commit. When the work is complete and you have evidence (build output, test results, diffs), call submit_for_completion with task_id={taskId}, a concise summary, and that evidence. Do NOT push or merge — the Coordinator integrates after verification.''',
  OrchestratorPromptField.workerKickoff:
      'Begin implementing your assigned task (#{taskId}) now. Work autonomously and commit to branch "{branch}".',
  OrchestratorPromptField.workerContinue:
      'Continue. If the task is fully implemented and committed to "{branch}", call submit_for_completion with task_id={taskId}, a summary, and your evidence. Otherwise keep working.',
  OrchestratorPromptField.verifyFraming: '''
=== TASK UNDER VERIFICATION ===
Task #{taskId}: {title}
Verification (what to run/check to prove completion): {verification}
Acceptance criteria: {acceptanceCriteria}
Work is on branch "{branch}" (already checked out).''',
  OrchestratorPromptField.verifyKickoff:
      'Verify task #{taskId}. First call run_verification, then execute the stated verification, then call submit_verdict with task_id={taskId}, passed=true|false, and your evidence.',
  OrchestratorPromptField.verifyContinue:
      'Finish verifying task #{taskId}: run the verification and call submit_verdict with the result.',
  OrchestratorPromptField.mergeFraming: '''
=== TASK TO INTEGRATE ===
Task #{taskId}: {title}
Work branch: "{branch}". The worktree is on "{targetBranch}".

Merge "{branch}" into "{targetBranch}" with git_merge, then call approve_task with task_id={taskId} to mark it Done. If git_merge reports conflicts, do NOT force it — call reject_task with task_id={taskId} and a note so the worker can rebase.''',
  OrchestratorPromptField.mergeKickoff:
      'Integrate task #{taskId}: merge "{branch}" into "{targetBranch}", then approve_task to finish it.',
  OrchestratorPromptField.mergeContinue:
      'Finish integrating task #{taskId}: complete the merge of "{branch}" into "{targetBranch}" and call approve_task (or reject_task on conflict).',
  OrchestratorPromptField.discoverySystem: '''
You are the project Coordinator running the post-setup DISCOVERY interview for "{projectName}". Setup is done; NO tasks exist yet. Your job is to flesh the idea out into a well-structured USER-STORY TREE before any work is created.

HOW TO INTERVIEW
- Have a natural conversation: ask ONE focused question at a time and build on the user's answers. Don't interrogate.
- As the idea takes shape, capture each distinct piece as a user story via `add_user_story` — a clear title and a narrative "As a <role>, I want <goal>, so that <benefit>", with acceptance_criteria when known.
- When the user gives you a BIG chunk describing several things at once, do NOT hand-write many stories from the full conversation — call `draft_stories_from_text` with their raw words. A focused helper splits + rephrases it into clean stories (with notes) for you; then nest/order them with `move_user_story`.

BUILD A REAL TREE (this is your responsibility — the user should NEVER have to tell you how to structure it):
- The single root is the overall product/epic. Everything else hangs UNDER something meaningful.
- Group related work under intermediate parent stories (feature areas / user flows), and nest sub-stories under THOSE. Do NOT put every story directly under the root — a flat list is wrong.
- CHAIN the steps of a flow: each step's `parent_story_id` is the story it follows from, so a linear flow becomes a parent→child→grandchild chain, not a row of siblings. (e.g. "Home" → "Map & Location" → "Find Closest Stand" → "Stand Detail" → "Start Order" — each the CHILD of the previous.)
- `add_user_story` returns the new id — reuse that id as the `parent_story_id` for its children. Use `list_user_stories` whenever you're unsure of an id or the current shape.
- Keep sibling ORDER meaningful (the order you add them, or set it explicitly). If the tree comes out wrong, FIX it with `move_user_story` to re-parent/re-order — never leave it flat or out of order.

DO NOT BE EAGER
- You CANNOT and MUST NOT create tasks — there are no task tools here on purpose.
- When the tree is solid, well-nested, and covers the idea, tell the user it looks ready and that they can press "Generate tasks from stories" when happy — the tasks are built from these stories.''',
};

/// Values to substitute into a template's placeholders for a given task.
class PromptVars {
  final int taskId;
  final String title;
  final String branch;

  /// The branch this task integrates into: the parent task's work branch for a
  /// subtask, otherwise the trunk ("main").
  final String targetBranch;
  final String description;
  final String acceptanceCriteria;
  final String verification;

  const PromptVars({
    required this.taskId,
    required this.title,
    required this.branch,
    this.targetBranch = 'main',
    this.description = '',
    this.acceptanceCriteria = '',
    this.verification = '',
  });

  String _orNone(String s) => s.trim().isEmpty ? '(none provided)' : s.trim();

  String apply(String template) => template
      .replaceAll('{taskId}', '$taskId')
      .replaceAll('{title}', title)
      .replaceAll('{branch}', branch)
      .replaceAll('{targetBranch}', targetBranch)
      .replaceAll('{description}', _orNone(description))
      .replaceAll('{acceptanceCriteria}', _orNone(acceptanceCriteria))
      .replaceAll('{verification}', _orNone(verification));
}

/// Resolved orchestrator prompt templates for a project: per-project overrides
/// (from the project's `orchestratorPromptsJson`) merged over the built-in
/// defaults. Unset fields fall back to [OrchestratorPromptFieldX.defaultValue].
class OrchestratorPrompts {
  /// Only the fields the project has explicitly overridden.
  final Map<OrchestratorPromptField, String> overrides;
  const OrchestratorPrompts(this.overrides);

  static const OrchestratorPrompts defaults = OrchestratorPrompts({});

  factory OrchestratorPrompts.fromJson(String? json) {
    final map = <OrchestratorPromptField, String>{};
    if (json != null && json.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map) {
          for (final field in OrchestratorPromptField.values) {
            final v = decoded[field.key];
            if (v is String && v.trim().isNotEmpty) map[field] = v;
          }
        }
      } catch (_) {}
    }
    return OrchestratorPrompts(map);
  }

  /// The effective template for [field]: the project override if present and
  /// non-empty, else the built-in default.
  String raw(OrchestratorPromptField field) =>
      overrides[field] ?? field.defaultValue;

  /// Render [field] with [vars] substituted.
  String render(OrchestratorPromptField field, PromptVars vars) =>
      vars.apply(raw(field));

  /// Serialize only the overrides (empty/default fields are omitted). Returns
  /// null when there are no overrides, so the column stays NULL.
  static String? toJson(Map<OrchestratorPromptField, String> overrides) {
    final map = <String, String>{};
    overrides.forEach((field, value) {
      final trimmed = value.trim();
      // Don't persist a value identical to the default — keep overrides minimal.
      if (trimmed.isNotEmpty && trimmed != field.defaultValue.trim()) {
        map[field.key] = value;
      }
    });
    return map.isEmpty ? null : jsonEncode(map);
  }
}
