// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
// Backward-compat types (InferenceClient = InferenceBackend).
import 'package:nexus_projects_client/infrastructure/inference/inference_client.dart';
import 'package:nexus_projects_client/features/projects/coordinator_tools.dart';
import 'package:nexus_projects_client/features/agents/agent_tool_permissions.dart';
import 'package:nexus_projects_client/features/project_plans/plan_store.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace.dart';
import 'package:nexus_projects_client/infrastructure/workspace/git/nxtprj_git_engine.dart';
import 'package:nexus_projects_client/infrastructure/build/build_service.dart';
import 'package:nexus_projects_client/core/agents/loop_guard.dart';

/// Manages a conversation with a Project's Coordinator AI (the "main brain").
/// Now supports real tool execution against the live DB so the AI can adjust
/// plans and tasks during text or voice conversations.
class ProjectCoordinatorSession {
  /// Concrete inference backend for this session.
  final InferenceBackend client;
  final int projectId;
  final String projectName;
  final NexusDatabase? db; // When provided, enables live tool execution + rich context

  /// The chat model to use. When null/empty we fall back to a generic id, but
  /// callers should pass the server's selected model so requests don't 404.
  final String? model;

  /// When this conversation is about a specific plan, the AI can read/rewrite it
  /// (view_plan / update_plan) and any tasks it creates record the provenance.
  /// This is the plan's workspace path, e.g. `/PLANS/Roadmap.md`.
  final String? openPlanPath;

  /// Filesystem-backed plan store for the project workspace; enables the plan
  /// tools (plans are real files under /PLANS, not DB rows).
  final PlanStore? planStore;

  /// The persisted chat session this conversation belongs to (for task provenance).
  final int? chatSessionPk;

  /// Tool-safety: the active agent's effective tool permissions and the
  /// human-approval hook for "ask" tools. [agentName] is used in messages.
  final AgentToolPermissions permissions;
  final Future<bool> Function(String tool, String summary)? confirmAsk;
  final String agentName;

  /// Workspace + git + build access for the file/git/build tools. Optional so a
  /// session can run without them (tools just report "unavailable").
  final Workspace? workspace;
  final NxtprjGitEngine? git;
  final BuildService? buildService;

  /// When set, replaces the built-in Coordinator system prompt entirely. The
  /// autonomous worker-spawn loop uses this to give an ephemeral worker its
  /// role-specific prompt (defaultSystemPrompt(role)) plus the task brief.
  final String? systemPromptOverride;

  final List<Map<String, dynamic>> _history = [];

  /// Detects when the coordinator agent gets stuck repeating the same tool call
  /// (same name + args) across rounds/turns and escalates warn → block so the
  /// model breaks out instead of burning rounds. The round cap is the backstop.
  final LoopGuard _loopGuard = LoopGuard();

  ProjectCoordinatorSession({
    required this.client,
    required this.projectId,
    required this.projectName,
    this.db,
    this.model,
    this.openPlanPath,
    this.planStore,
    this.chatSessionPk,
    this.permissions = AgentToolPermissions.allDefaults,
    this.confirmAsk,
    this.agentName = 'This agent',
    this.workspace,
    this.git,
    this.buildService,
    this.systemPromptOverride,
    this.enableThinking,
  });

  /// Effective model "thinking mode" for this session's requests: true/false
  /// forces `enable_thinking`; null omits it (model default). Resolved by the
  /// caller from the agent's (and, later, the task's) ThinkingMode.
  final bool? enableThinking;

  /// The model id actually sent to the backend.
  String get _effectiveModel =>
      (model != null && model!.trim().isNotEmpty) ? model!.trim() : 'default-coordinator';

  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  /// Builds rich live context from the DB when available (tasks + future plan metadata).
  Future<String> getRichProjectContext() async {
    if (db == null) {
      return 'Project "$projectName" (no live DB context available in this session).';
    }
    try {
      final tasks = await db!.getTasksForProject(projectId);
      if (tasks.isEmpty) {
        return 'Project "$projectName": No tasks yet. The user is likely starting planning.';
      }
      final buffer = StringBuffer();
      buffer.writeln('Project: $projectName (id: $projectId)');
      buffer.writeln('Current tasks (${tasks.length} total):');
      for (final t in tasks.take(12)) {
        final parent = t.task_parent_fk != null ? ' (sub of ${t.task_parent_fk})' : '';
        buffer.writeln('- ${t.title} [${t.priority}] — ${t.status}$parent');
      }
      if (tasks.length > 12) buffer.writeln('... and ${tasks.length - 12} more.');
      return buffer.toString();
    } catch (e) {
      return 'Project "$projectName": context temporarily unavailable ($e).';
    }
  }

  /// Builds the system prompt with current project context.
  Future<String> _buildSystemPrompt({String? currentPlanContext}) async {
    // An ephemeral worker/verifier session supplies its own complete prompt
    // (role brief + task context); use it verbatim instead of the Coordinator's.
    if (systemPromptOverride != null && systemPromptOverride!.trim().isNotEmpty) {
      return systemPromptOverride!;
    }
    final buffer = StringBuffer();
    buffer.writeln('You are the Coordinator AI for the project "$projectName".');
    buffer.writeln('You help the user plan, refine tasks, and make decisions for this project.');
    buffer.writeln('You have FULL ACCESS to live project state via tools. When the user asks to add work, change status, break down plans, or adjust direction — CALL THE TOOLS to do it immediately. Then confirm in natural language what you changed.');
    buffer.writeln('Keep spoken replies short and natural. Use tools proactively.');

    final live = currentPlanContext ?? await getRichProjectContext();
    if (live.isNotEmpty) {
      buffer.writeln('\nLive project context:\n$live');
    }

    // When focused on a plan, load its current document so the AI can adjust it.
    if (openPlanPath != null && planStore != null) {
      try {
        final content = await planStore!.read(openPlanPath!);
        final name = _basename(openPlanPath!);
        buffer.writeln('\nYou are editing the plan document "$name". Its current contents:\n"""\n$content\n"""');
        buffer.writeln('To change the plan, call update_plan with the full new contents (markdown). To re-read it, call view_plan. Tasks you create from this plan are automatically linked to it.');
      } catch (_) {}
    }

    final planFocus = openPlanPath != null ? 'view_plan, update_plan, ' : '';
    buffer.writeln('\nYou have FULL read/create/update/delete control. Available tools:');
    buffer.writeln('- Tasks: list_tasks, get_task, create_task (use parent_task_id for subtasks), update_task, update_task_status, set_task_dates, delete_task.');
    buffer.writeln('  Thinking mode: when you create_task/update_task you may set `thinking_enabled: true`, but ONLY when the task is a small, very specific, cut-and-dry job (one narrow, well-defined feature). Do NOT enable thinking for large, broad, or open-ended tasks — on long/open-ended context, thinking mode degrades the response and outcome by about 15%, making results worse. Default to leaving thinking_enabled off (omit it) unless the job is narrow and clearly scoped.');
    buffer.writeln('- Agents: list_agents (call this to discover who exists), assign_agent_to_task. ALWAYS list_agents before assigning so you use a real agent id.');
    buffer.writeln('CRITICAL: every task MUST be assigned to a worker agent. When you create_task, pass agent_persona_id (call list_agents first to pick the best-fit specialist). Never leave a task unassigned — an unassigned task is invisible to the orchestrator and never gets worked. If you create a task without naming an agent, a default worker is auto-assigned, but you should choose the right one.');
    buffer.writeln('- Plans→tasks: when the user changes the idea, edit the PLAN first — add/adjust "- [ ] …" outline items in the relevant plan doc (update_plan/write_plan). Every plan write AUTOMATICALLY creates tasks for any new outline items (each line is annotated with its task id, so edits never double-create). Tell the user which tasks were created. sync_plans_to_tasks is also available to run the same pass on demand.');
    buffer.writeln('- Plans: list_plans, create_plan, read_plan, write_plan, rename_plan, delete_plan, link_task_to_plan. ${planFocus.isNotEmpty ? '($planFocus operate on the currently-open plan.) ' : ''}');
    buffer.writeln('- Files (project workspace): list_files, read_file, write_file, create_directory, move_path, delete_path.');
    buffer.writeln('- Git (workspace repo): git_status, git_log, git_commit, git_branches, git_create_branch, git_checkout_branch.');
    buffer.writeln('- Build/CI: build_docker_image, run_workflow (GitHub-Actions YAML, runs locally), list_ci_runs, get_ci_run (read logs/errors to diagnose failures).');
    buffer.writeln('- Other: view_current_plan, generate_diagram, propose_plan_adjustment.');
    buffer.writeln('Prefer reading (list_/get_/read_) before mutating. Only delete when the user clearly asks.');
    buffer.writeln('After you call tools, ALWAYS follow up with a short spoken sentence telling the user what you found or did. Never end a turn with only tool calls and no words.');
    return buffer.toString();
  }

  Future<ChatCompletionResponse> sendMessage(
    String userMessage, {
    String? currentPlanContext,
    List<Map<String, dynamic>>? tools,
  }) async {
    final sys = await _buildSystemPrompt(currentPlanContext: currentPlanContext);
    final messages = _sanitizeForWire([
      {'role': 'system', 'content': sys},
      ..._history,
      {'role': 'user', 'content': userMessage},
    ]);

    final effectiveTools = tools ?? CoordinatorTools.buildToolSchemas();

    final response = await client.createChatCompletion(
      model: _effectiveModel,
      messages: messages,
      tools: effectiveTools,
      temperature: 0.7,
      enableThinking: enableThinking,
    );

    _history.add({'role': 'user', 'content': userMessage});
    if (response.choices.isNotEmpty) {
      final assistantMsg = response.choices.first.message;
      _history.add({
        'role': 'assistant',
        'content': assistantMsg.content,
        if (assistantMsg.toolCalls != null && assistantMsg.toolCalls!.isNotEmpty)
          'tool_calls': assistantMsg.toolCalls!.map((t) => {
                'id': t.id,
                'name': t.function.name,
                'arguments': t.function.arguments,
              }).toList(),
      });
    }

    return response;
  }

  /// Streaming version with automatic tool schema injection.
  /// After the stream yields ChatStreamFinish with toolCalls, the caller (chat screen)
  /// should call executeToolCalls to apply changes live, then optionally continue
  /// the conversation with the tool results appended.
  Stream<ChatStreamEvent> streamMessage(
    String userMessage, {
    String? currentPlanContext,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final sys = await _buildSystemPrompt(currentPlanContext: currentPlanContext);
    final messages = _sanitizeForWire([
      {'role': 'system', 'content': sys},
      ..._history,
      {'role': 'user', 'content': userMessage},
    ]);

    final effectiveTools = tools ?? CoordinatorTools.buildToolSchemas();

    yield* client.streamChatCompletion(
      model: _effectiveModel,
      messages: messages,
      tools: effectiveTools,
      temperature: 0.7,
      enableThinking: enableThinking,
    );
  }

  /// Runs one user turn with an internal tool loop, maintaining history in the
  /// proper OpenAI tool-calling format. Streams content deltas for the answer;
  /// executes any tool calls between rounds (reporting each via [onToolResult]),
  /// then loops so the model can speak a natural-language answer using the
  /// results. Ends when the model returns content with no tool calls (or the
  /// round cap is reached). This is what makes the AI actually reply after it
  /// calls tools like list_open_tasks / view_current_plan.
  Stream<ChatStreamEvent> runTurn(
    String userMessage, {
    void Function(String toolResult)? onToolResult,
    String? currentPlanContext,
    int maxToolRounds = 4,
  }) async* {
    _history.add({'role': 'user', 'content': userMessage});
    // If this turn fails we roll back to here so a failed/retried send never
    // leaves an orphan `user` message behind. Accumulating consecutive user
    // messages corrupts the chat template and makes the server reject (400) or
    // crash (empty 500) on subsequent turns.
    final rollbackTo = _history.length - 1;

    // Offer the plan tools whenever a plan store is available — not only when a
    // specific plan is open — so the coordinator can list/read/create plans in
    // the general project chat (PLANS/ exists from the start of planning).
    final tools = CoordinatorTools.buildToolSchemas(includePlanTools: planStore != null);
    final executor = db != null
        ? CoordinatorToolExecutor(db: db!, projectId: projectId, inference: client, chatSessionPk: chatSessionPk, openPlanPath: openPlanPath, planStore: planStore, permissions: permissions, confirmAsk: confirmAsk, agentName: agentName, workspace: workspace, git: git, buildService: buildService)
        : null;

    try {
      for (var round = 0; round < maxToolRounds; round++) {
        final sys = await _buildSystemPrompt(currentPlanContext: currentPlanContext);
        final messages = _sanitizeForWire([
          {'role': 'system', 'content': sys},
          ..._history,
        ]);

        // Stream the round: content deltas are forwarded live so the UI renders
        // token-by-token; tool calls are captured from the final finish event.
        final buf = StringBuffer();
        var toolCalls = const <ToolCall>[];
        var toolsDropped = false;
        await for (final ev in _streamRound(messages, tools, onToolsDropped: (d) => toolsDropped = d)) {
          if (ev is ChatContentDelta) {
            buf.write(ev.text);
            yield ev; // forward live (do NOT also re-yield the full content below)
          } else if (ev is ChatStreamFinish) {
            toolCalls = ev.toolCalls;
          }
        }
        final contentStr = buf.toString();
        if (toolsDropped && round == 0) {
          onToolResult?.call('(This model rejected tool-calling, so live task/plan actions are off for this reply.)');
        }

        // Record the assistant message in history. When there are tool calls and
        // no text, content must be null (not "") — servers reject empty-string
        // content alongside tool_calls.
        _history.add({
          'role': 'assistant',
          'content': (toolCalls.isNotEmpty && contentStr.isEmpty) ? null : contentStr,
          if (toolCalls.isNotEmpty)
            'tool_calls': [
              for (final t in toolCalls)
                {
                  'id': t.id,
                  'type': 'function',
                  'function': {'name': t.function.name, 'arguments': t.function.arguments},
                }
            ],
        });

        if (toolCalls.isEmpty || executor == null) {
          yield ChatStreamFinish(finishReason: 'stop', toolCalls: const [], contentSoFar: contentStr);
          return;
        }

        // Execute each tool call, append results, then loop for the spoken answer.
        for (final call in toolCalls) {
          Map<String, dynamic> args = {};
          try {
            final raw = call.function.arguments.trim();
            if (raw.startsWith('{')) args = (jsonDecode(raw) as Map).cast<String, dynamic>();
          } catch (_) {}

          final action = _loopGuard.observe(call.function.name, args);
          if (action == LoopAction.block) {
            final note = _loopGuard.feedback(call.function.name, action);
            onToolResult?.call(note);
            _history.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': note,
            });
            continue; // refuse the looping call; model must change course
          }

          final result = await executor.execute(name: call.function.name, args: args);
          // Show only a short summary in the chat — big payloads (a whole plan or
          // file the model read) shouldn't flood the transcript. The MODEL still
          // receives the full result via `body`/history below.
          onToolResult?.call(_summarizeToolResult(result));
          final body = action == LoopAction.warn
              ? '$result\n\n${_loopGuard.feedback(call.function.name, action)}'
              : result;
          _history.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'content': body,
          });
        }
      }
    } catch (e) {
      // Drop everything this turn added (user message + any partial assistant/
      // tool messages) so the conversation stays well-formed for the next try.
      if (rollbackTo < _history.length) _history.removeRange(rollbackTo, _history.length);
      rethrow;
    }

    // Hit the round cap — finish gracefully.
    yield const ChatStreamFinish(finishReason: 'length', toolCalls: [], contentSoFar: '');
  }

  /// A short, UI-friendly version of a tool result so large payloads (e.g. an
  /// entire plan/file the model read) don't flood the chat transcript. The model
  /// still gets the full result in history; only the on-screen note is summarized.
  static String _summarizeToolResult(String result) {
    final trimmed = result.trim();
    const cap = 200;
    final lineCount = '\n'.allMatches(trimmed).length + 1;
    // Short single-line results are already their own summary — show as-is.
    if (trimmed.length <= cap && lineCount == 1) return trimmed;
    final firstLine = trimmed.split('\n').first.trim();
    final head = firstLine.length > cap
        ? '${firstLine.substring(0, cap).trimRight()}…'
        : firstLine;
    final more = lineCount - 1;
    return more > 0 ? '$head  (+$more more line${more == 1 ? '' : 's'})' : '$head…';
  }

  /// Repairs a message list for the wire. Failed turns can leave a run of
  /// consecutive `user` (or `assistant`) text messages in history; chat
  /// templates expect alternating roles, and this server rejects/crashes on
  /// long same-role runs. We merge consecutive same-role *text* messages into
  /// one. Messages carrying tool_calls and `tool`-role results are left intact
  /// (they must keep their exact structure for tool-calling to work).
  static List<Map<String, dynamic>> _sanitizeForWire(List<Map<String, dynamic>> msgs) {
    final out = <Map<String, dynamic>>[];
    for (final m in msgs) {
      final role = m['role'];
      final hasToolCalls = m['tool_calls'] != null;
      if (out.isNotEmpty &&
          !hasToolCalls &&
          (role == 'user' || role == 'assistant') &&
          out.last['role'] == role &&
          out.last['tool_calls'] == null) {
        final prev = (out.last['content'] ?? '').toString();
        final cur = (m['content'] ?? '').toString();
        out.last['content'] = prev.isEmpty ? cur : (cur.isEmpty ? prev : '$prev\n$cur');
        continue;
      }
      out.add(Map<String, dynamic>.from(m));
    }
    return out;
  }

  /// Runs ONE model round, STREAMING as the PRIMARY path so the reply renders
  /// token-by-token. Falls back to a NON-streaming request if streaming errors
  /// before any content was emitted (some llama.cpp/GGUF backends reject
  /// streaming-with-tools), and finally retries WITHOUT tools if the request
  /// itself is rejected so plain chat still works. Yields [ChatContentDelta] as
  /// tokens arrive and a final [ChatStreamFinish] carrying the assembled tool
  /// calls; [onToolsDropped] reports whether tools were dropped.
  Stream<ChatStreamEvent> _streamRound(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools, {
    required void Function(bool dropped) onToolsDropped,
  }) async* {
    // Primary: streaming WITH tools.
    var emitted = false;
    try {
      await for (final ev in client.streamChatCompletion(
        model: _effectiveModel,
        messages: messages,
        tools: tools,
        temperature: 0.7,
        enableThinking: enableThinking,
      )) {
        emitted = true;
        yield ev;
      }
      onToolsDropped(false);
      return;
    } catch (_) {
      // If partial content already streamed we can't safely retry — rethrow.
      if (emitted) rethrow;
      // Otherwise fall through to the non-streaming fallbacks below.
    }

    // Fallback 1: non-streaming WITH tools.
    try {
      yield* _nonStreamingRound(messages, tools);
      onToolsDropped(false);
      return;
    } catch (_) {
      // Fall through to no-tools.
    }

    // Fallback 2: non-streaming WITHOUT tools (the request itself was rejected).
    yield* _nonStreamingRound(messages, null);
    onToolsDropped(true);
  }

  /// One non-streaming round mapped into the same event shape as streaming.
  Stream<ChatStreamEvent> _nonStreamingRound(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
  ) async* {
    final resp = await client.createChatCompletion(
      model: _effectiveModel,
      messages: messages,
      tools: tools,
      temperature: 0.7,
      enableThinking: enableThinking,
    );
    final msg = resp.choices.isNotEmpty ? resp.choices.first.message : null;
    final content = msg?.content ?? '';
    if (content.isNotEmpty) yield ChatContentDelta(content);
    yield ChatStreamFinish(
      finishReason: 'stop',
      toolCalls: msg?.toolCalls ?? const <ToolCall>[],
      contentSoFar: content,
    );
  }

  /// Executes a batch of tool calls (from ChatStreamFinish) against the live DB.
  /// Returns human-readable results for each. Appends tool messages to history
  /// so subsequent turns see the outcomes.
  Future<List<String>> executeToolCalls(List<ToolCall> toolCalls) async {
    if (db == null || toolCalls.isEmpty) {
      return toolCalls.map((c) => 'Tool ${c.function.name} not executed (no DB or empty calls).').toList();
    }

    final executor = CoordinatorToolExecutor(
      db: db!,
      projectId: projectId,
      inference: client,
      chatSessionPk: chatSessionPk,
      openPlanPath: openPlanPath,
      planStore: planStore,
      permissions: permissions,
      confirmAsk: confirmAsk,
      agentName: agentName,
      workspace: workspace,
      git: git,
      buildService: buildService,
    );

    final results = <String>[];
    for (final call in toolCalls) {
      Map<String, dynamic> args = {};
      try {
        final raw = call.function.arguments.trim();
        if (raw.startsWith('{')) {
          args = (jsonDecode(raw) as Map).cast<String, dynamic>();
        }
      } catch (_) {
        args = {};
      }

      final resultText = await executor.execute(
        name: call.function.name,
        args: args,
      );
      results.add(resultText);

      // Append as tool result to history for the model to see on next turn / next voice turn
      _history.add({
        'role': 'tool',
        'tool_call_id': call.id,
        'name': call.function.name,
        'content': resultText,
      });
    }

    return results;
  }

  void clearHistory() {
    _history.clear();
    _loopGuard.reset();
  }

  /// Seed conversation history when resuming a persisted session, so the model
  /// has prior context. Pass user/assistant text turns in chronological order.
  void restoreHistory(Iterable<({String role, String content})> turns) {
    _history
      ..clear()
      ..addAll(turns.map((t) => {'role': t.role, 'content': t.content}));
  }

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}
