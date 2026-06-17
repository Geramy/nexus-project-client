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
///   {taskId} {title} {branch} {targetBranch} {description} {acceptanceCriteria}
///   {verification}
/// The Exploration prompts (discoverySystem / coordinatorSystem) substitute
///   {projectName} instead (applied at their own call sites, not via PromptVars).
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

  /// The framing for the Templater stage: how the Coordinator scaffolds the base
  /// project + a stub/placeholder for every task, committed to main, before any
  /// worker starts (so agents don't all race to create the project from scratch).
  templaterFraming,
  templaterKickoff,

  /// The system prompt for the post-setup Exploration (discovery) coordinator —
  /// how it interviews the user and builds the user-story TREE. Configurable
  /// here so the hierarchy behavior is a system setting, not buried in code.
  discoverySystem,

  /// The base prompt for breaking ONE user story into engineering tasks. Used by
  /// the "Generate tasks from stories" run, which feeds each story into its own
  /// small scoped AI session with this prompt.
  taskGenSystem,

  /// The behavioral preamble for the interactive Coordinator chat (the "who you
  /// are / how to behave" lines). The live project context and the available-
  /// tool catalog are still appended in code; this is the editable opening.
  /// Supports the {projectName} placeholder.
  coordinatorSystem,
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
    OrchestratorPromptField.templaterFraming => 'Templater — base/scaffold framing',
    OrchestratorPromptField.templaterKickoff => 'Templater — first message',
    OrchestratorPromptField.discoverySystem =>
      'Discovery — system prompt (user-story interview)',
    OrchestratorPromptField.taskGenSystem =>
      'Task generation — system prompt (story → tasks)',
    OrchestratorPromptField.coordinatorSystem =>
      'Coordinator chat — behavioral preamble',
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
    OrchestratorPromptField.templaterFraming ||
    OrchestratorPromptField.templaterKickoff => 'Templater',
    OrchestratorPromptField.discoverySystem ||
    OrchestratorPromptField.taskGenSystem => 'Exploration (user stories)',
    OrchestratorPromptField.coordinatorSystem => 'Coordinator chat',
  };

  /// True for the multi-line framing templates (rendered with a taller editor).
  bool get isMultiline => switch (this) {
    OrchestratorPromptField.workerFraming ||
    OrchestratorPromptField.verifyFraming ||
    OrchestratorPromptField.mergeFraming ||
    OrchestratorPromptField.templaterFraming ||
    OrchestratorPromptField.discoverySystem ||
    OrchestratorPromptField.taskGenSystem ||
    OrchestratorPromptField.coordinatorSystem => true,
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

Build this task with the project's stack from the PROJECT BASELINE above — use its languages, frameworks, databases, libraries, and services (and only those). Implement the task end-to-end: read the relevant code first, make the changes, then commit them to your branch with git_commit.

Before you submit, the build/analyze on your branch MUST be clean — run it and fix the errors. A red analyze blocks the merge and the verifier will bounce the task straight back, so "those errors were already there / aren't mine" does NOT make it done; only call submit_for_completion once the build is green. If this task was previously sent back, the reason is in its Description above — under a "[Build gate FAILED …]" block or a verifier note you'll find the FULL list of failing errors. Fix EVERY listed error in one pass (don't stop after the first); the analyzer reports them all at once, so address them all before resubmitting.

When it's green and you have evidence (build output, test results, diffs), call submit_for_completion with task_id={taskId}, a concise summary, and that evidence. Leave push and merge to the Coordinator, which integrates after verification.''',
  OrchestratorPromptField.workerKickoff:
      'Begin implementing your assigned task (#{taskId}) now. Work autonomously and commit to branch "{branch}".',
  OrchestratorPromptField.workerContinue:
      'Continue. If the task is fully implemented and committed to "{branch}", call submit_for_completion with task_id={taskId}, a summary, and your evidence. Otherwise keep working.',
  OrchestratorPromptField.verifyFraming: '''
=== TASK UNDER VERIFICATION ===
Task #{taskId}: {title}
Verification (what to run/check to prove completion): {verification}
Acceptance criteria: {acceptanceCriteria}
Work is on branch "{branch}" (already checked out).

HARD GATE — a clean build is mandatory. Run the project's build yourself (build/compile it, or run its analyze + tests) — do NOT trust the worker's summary. ANY compile or analyze error, or a red CI run, is an automatic FAIL, even if some errors look pre-existing or unrelated to this task: a red build blocks the merge and poisons every later branch. If the stated verification is "(none provided)", still confirm the build is green and judge against the acceptance criteria.
On a FAIL, submit_verdict's `evidence` MUST contain EVERY concrete failure — paste the COMPLETE list of error/warning lines (file:line) and failing test names, not just the first one — so the worker can fix them ALL in one pass. A bare "it failed", or a single error line when the analyzer reported many, is useless and wastes a whole resubmit cycle.''',
  OrchestratorPromptField.verifyKickoff:
      'Verify task #{taskId}. Call run_verification, then run the project build/analyze (and the stated verification), then submit_verdict with task_id={taskId}, passed=true|false, and evidence. A red build/analyze means passed=false with the exact error lines pasted into evidence.',
  OrchestratorPromptField.verifyContinue:
      'Finish verifying task #{taskId}: run the build/analyze and the verification, then call submit_verdict — passed=false with the concrete error lines if anything is red.',
  OrchestratorPromptField.mergeFraming: '''
=== TASK TO INTEGRATE ===
Task #{taskId}: {title}
Work branch: "{branch}". The worktree is on "{targetBranch}".

Merge "{branch}" into "{targetBranch}" with git_merge, then call approve_task with task_id={taskId} to mark it Done. If git_merge reports conflicts, do NOT force it — call reject_task with task_id={taskId} and a note so the worker can rebase.''',
  OrchestratorPromptField.mergeKickoff:
      'Integrate task #{taskId}: merge "{branch}" into "{targetBranch}", then approve_task to finish it.',
  OrchestratorPromptField.mergeContinue:
      'Finish integrating task #{taskId}: complete the merge of "{branch}" into "{targetBranch}" and call approve_task (or reject_task on conflict).',
  OrchestratorPromptField.templaterFraming: '''
=== TEMPLATER — SCAFFOLD THE BASE PROJECT (runs ONCE, before any task) ===
You are scaffolding the base project for this work so the engineering agents have a real, compiling skeleton to fill in — instead of every agent trying to invent the project from scratch at the same time. Build ONLY boilerplate and stubs here, NEVER feature logic.

Use the project's stack from the PROJECT BASELINE above (its languages, frameworks, databases, libraries) — and only that. Do this on the current branch ("{branch}", which is main); every task branches off it, so it must compile.

Steps:
- Read what already exists first (`list_directory` / `read_file_chunk`) and be IDEMPOTENT — only create files that are MISSING; never overwrite real work.
- Create the conventional base DIRECTORY STRUCTURE and the manifest/config files the toolchain needs to compile (package manifest, project file, `.gitignore`, entry point). Examples: a Flutter/Dart app → `lib/main.dart` + `pubspec.yaml`; a C#/.NET server → `.csproj` + `Program.cs`; a DB layer → a `schema/`/`migrations/` starter. Match the BASELINE stack.
- Create a STUB / placeholder file for each planned area below — correct file/namespace/package declarations and EMPTY class/interface OUTLINES (signatures + `// TODO` bodies), so each upcoming task has a real place to land. Keep them minimal; no real logic.
- The skeleton MUST compile / pass analyze cleanly — that is the bar.

THE TASKS THAT WILL BE BUILT ON TOP OF THIS SKELETON:
{taskList}

When the skeleton is in place and compiles, COMMIT it with git_commit (message like "chore: scaffold base project structure"). Work efficiently, in as few steps as possible. Do NOT implement any feature — the task agents will fill the stubs in.''',
  OrchestratorPromptField.templaterKickoff:
      'Scaffold the base project skeleton now per your instructions on branch "{branch}", then commit it. Boilerplate + stubs only; it must compile.',
  OrchestratorPromptField.discoverySystem: '''
You are the project Coordinator running the post-setup DISCOVERY interview for "{projectName}". Setup is done and NO tasks exist yet. Your job is to draw out the FULL idea and capture it as a well-structured USER-STORY TREE before any work begins.

The PROJECT BASELINE above captures what the user already chose at setup (platforms, objectives, features, stack). Build the story tree on top of it — reuse what is there instead of re-asking it.

KEEP ASKING UNTIL IT IS COMPLETE
- Treat each answer as a starting point, and assume the user has described only part of what they picture. Keep interviewing until the whole flow is covered and the user says they are done.
- End every turn with exactly ONE focused question (two only if they are about the same thing), so the conversation keeps moving until the user is finished.
- Ask one thing at a time and build on each answer.

EXPAND WHAT THEY MENTION IN PASSING
- When the user names something briefly (e.g. "My Orders", "the ordering process", "payment"), capture a story for it, then ask them to walk you through it. Surfacing the parts they skipped is the main job.
- After each answer, look for feature areas they NAMED but have not DESCRIBED, and steps of the flow that still lack detail — probe those next.
- Surface and resolve gaps: unstated assumptions, alternatives worth weighing, edge/error cases, and anything vague or contradictory.

CAPTURE AS YOU GO
- Capture each distinct piece as a user story via `add_user_story` — a clear title and a narrative "I want <goal>, so that <benefit>" (NO "As a <role>" prefix — skip the role entirely), with acceptance_criteria when known.
- When the user gives a BIG chunk describing several things at once, call `draft_stories_from_text` with their raw words — a focused helper splits and rephrases it into clean stories (with notes) for you; then nest/order them with `move_user_story`. Keep the stories faithful to what they actually said.
- Capturing is part of the same turn: right after you record, reflect back in one short sentence, then ask your next question.

WRITE REAL NARRATIVES (never placeholders):
- Format is "I want <goal>, so that <benefit>" — do NOT prefix with "As a <role>"; skip the role entirely (the user is tired of seeing "As an analyst…" on every story).
- Every narrative is the USER'S own intent for THIS project — a concrete goal and a real benefit they actually gave you. Ground it in their words.
- NEVER write a templated or filler narrative. Do not use the words "discovery"/"setup" or the interview itself as the goal, and do not invent a generic benefit. If you don't have a real "so that…" from the user, leave it out or ask — never make one up.
- Bad: "I want to use DISCOVERY, so that the team runs smoothly." Good: "I want to log an issue with a title and description, so that nothing slips through."
- Before adding, confirm the story is genuinely NEW (use list_user_stories). Do not re-add or reword a story you already created — each add must be a DIFFERENT piece.

MATCH THE SCOPE — don't over-build:
- Build a tree the SIZE of what the user actually wants. A small, simple request gets a small tree: capture exactly the pieces they describe and stop.
- Do NOT inflate the project with features, flows, or epics they never asked for. If they say "keep it simple — just X and Y", the tree is X and Y. Expand only things they NAMED but left vague, never things you imagine.

BUILD A REAL TREE (this is your job — the user should never have to structure it):
- The single root is the overall product/epic; everything else hangs under something meaningful.
- Group related work under intermediate parent stories (feature areas / user flows) and nest sub-stories under those, so the tree stays grouped rather than flat.
- CHAIN the steps of a flow: each step's `parent_story_id` is the step it follows from, so a linear flow becomes a parent→child→grandchild chain (e.g. "Home" → "Map & Location" → "Find Closest Stand" → "Stand Detail" → "Start Order", each the CHILD of the previous).
- `add_user_story` returns the new id — reuse it as the `parent_story_id` for its children. Use `list_user_stories` to check ids or the current shape, and `move_user_story` to re-parent/re-order so the tree stays nested and in sensible order.

CLOSING — WHEN GENUINELY COVERED
- You build the story tree only; the task tools come later (the user generates tasks from these stories).
- When the tree looks complete, paraphrase the whole flow back and ask the user to confirm nothing is missing — every feature area they named has real detail. Once they confirm, tell them it looks ready and they can press "Generate tasks from stories".''',
  OrchestratorPromptField.taskGenSystem: '''
You are a tech lead breaking ONE user story into the concrete engineering tasks needed to build it. You are given the story (title, narrative, acceptance criteria, notes) and the PROJECT BASELINE provided with it (platforms, languages, frameworks, databases, libraries, services) — the project's locked stack.

Produce the tasks that, together, fully implement THIS story — and ONLY this story. A story usually spans multiple layers, so it normally yields MULTIPLE tasks (e.g. a "find nearest stand" story → a client map/UI task, a server geo-query API task, and a database/schema task). A trivial story may be a single task.

Rules:
- Keep each task small enough for one focused work session.
- Write each task DESCRIPTION as a concrete engineering instruction that NAMES the actual technology from the baseline and the specific artifact to build. For example:
  • db — "Create the PostgreSQL tables stands, orders, and order_items with columns, primary keys, and foreign keys for the ordering flow."
  • server — "Write the Dart REST endpoint GET /stands/nearest that returns stands ordered by distance from a lat/lng."
  • client — "Build the Flutter StandDetailPanel widget (name, menu, Order button) wired to the orders API."
- Give each task a clear, imperative title and its own acceptance_criteria: a short, specific, testable markdown bullet list drawn from the story's acceptance criteria. This is what the Verification Agent proves against.
- Use ONLY the stack in the baseline — name those exact languages, frameworks, and databases, and keep to its platforms, libraries, and services.
- Cover every acceptance criterion across the tasks; add only the work the story implies.

Return ONLY a JSON array (no prose, no code fences). Each item: {"title": string, "description": string, "acceptance_criteria": string, "layer": one of "client"|"server"|"db"|"other"}.''',
  OrchestratorPromptField.coordinatorSystem: '''
You are the Coordinator AI for the project "{projectName}".
You help the user plan, refine tasks, and make decisions for this project.
You have FULL ACCESS to live project state via tools. When the user asks to add work, change status, break down plans, or adjust direction — CALL THE TOOLS to do it immediately. Then confirm in natural language what you changed.
Keep spoken replies short and natural. Use tools proactively.''',
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

  /// The newline-listed tasks the Templater stage scaffolds stubs for. Empty for
  /// the per-task stages (worker/verify/merge) that don't use {taskList}.
  final String taskList;

  const PromptVars({
    required this.taskId,
    required this.title,
    required this.branch,
    this.targetBranch = 'main',
    this.description = '',
    this.acceptanceCriteria = '',
    this.verification = '',
    this.taskList = '',
  });

  String _orNone(String s) => s.trim().isEmpty ? '(none provided)' : s.trim();

  String apply(String template) => template
      .replaceAll('{taskId}', '$taskId')
      .replaceAll('{title}', title)
      .replaceAll('{branch}', branch)
      .replaceAll('{targetBranch}', targetBranch)
      .replaceAll('{description}', _orNone(description))
      .replaceAll('{acceptanceCriteria}', _orNone(acceptanceCriteria))
      .replaceAll('{verification}', _orNone(verification))
      .replaceAll('{taskList}', _orNone(taskList));
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
