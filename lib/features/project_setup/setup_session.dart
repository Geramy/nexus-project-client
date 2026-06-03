// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../../core/agents/loop_guard.dart';
import '../../infrastructure/inference/inference_backend.dart';
import 'config/setup_flow.dart';
import 'setup_tools.dart';

/// Two stages of the setup host: the bounded multiple-choice [interview], and
/// the post-finalize [refine] stage where plans exist and the user enriches
/// them with free-text descriptions that the host folds into the plan files.
enum SetupPhase { interview, refine }

/// Drives the bounded Project Setup interview. The AI hosts the conversation and
/// writes rationale, but every decision flows through [SetupTools]: it asks the
/// user multiple-choice questions, verifies libraries against the registries,
/// proposes tags (always `proposed`), and finalizes by generating /PLANS files.
/// A deterministic resolver — never the AI — computes the stack at finalize.
class SetupSession {
  SetupSession({
    required this.client,
    required this.model,
    required this.projectName,
    required this.executor,
    required this.flow,
    this.maxToolRounds = 40,
    this.enableThinking,
    this.leanContext = true,
  });

  final InferenceBackend client;
  final String model;
  final String projectName;
  final SetupToolExecutor executor;

  /// When true (default), reconstruct state from the board (DB) + a short turn
  /// window instead of replaying the whole transcript, and drop the interview
  /// context at finalize. When false, send the full history every turn.
  final bool leanContext;

  /// The configurable, DB-resolved interview definition (stages + guidance) for
  /// this project's type + sub-category. Drives the interview prompt + the
  /// `propose_tags` categories.
  final SetupFlowDefinition flow;
  final int maxToolRounds;
  /// Effective enable_thinking for this session (null omits the param). Resolved
  /// from the project agent's ThinkingMode.
  final bool? enableThinking;

  /// Working LLM context — TRIMMED each turn to the recent window and CLEARED at
  /// the interview→refine boundary. The board (DB) is the durable state, so we
  /// never need to replay the whole conversation to the model.
  final List<Map<String, dynamic>> _history = [];

  /// Append-only record of user/assistant TEXT, decoupled from [_history] so the
  /// persisted transcript (and UI restore) survives the working-context trim.
  final List<Map<String, dynamic>> _transcript = [];

  /// How many recent user-initiated turns of [_history] to send each request.
  /// Older turns are represented by the injected board-state summary.
  static const int _historyWindowTurns = 4;

  /// Set once the interview history has been dropped on entering refine, so the
  /// hard-drop happens exactly at the boundary.
  bool _interviewDropped = false;

  /// Internal nudge injected to unstick a stalled turn; filtered out of the
  /// persisted transcript so it never shows to the user.
  static const String _continueNudge =
      'Continue: take the next step now — ask the next question or call the needed tool.';

  /// Which stage the host is in. Starts in [SetupPhase.interview]; flips to
  /// [SetupPhase.refine] once `finalize_setup` has generated the plan files.
  SetupPhase phase = SetupPhase.interview;

  void enterRefinePhase() => phase = SetupPhase.refine;

  /// Detects when the interview agent gets stuck re-issuing the same tool call
  /// (e.g. re-asking the same question or re-proposing the same tags). Lives at
  /// session scope so it catches loops that span user turns, not just one turn.
  final LoopGuard _loopGuard = LoopGuard();

  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  String get _effectiveModel =>
      model.trim().isEmpty ? 'default-coordinator' : model.trim();

  String _systemPrompt() =>
      phase == SetupPhase.refine ? _refinePrompt() : _interviewPrompt();

  /// Categories the active flow proposes into (its stage keys) — drives the
  /// `propose_tags` schema so each project type proposes its own sections.
  List<String> get tagCategories => flow.stages.map((s) => s.key).toList();

  String _interviewPrompt() {
    final stages = StringBuffer();
    for (var i = 0; i < flow.stages.length; i++) {
      final s = flow.stages[i];
      stages.writeln('${i + 1}. ${s.title} (category `${s.key}`): ${s.guidance}');
      if (s.vocab == SetupVocab.closed && s.suggestions.isNotEmpty) {
        stages.writeln('   Allowed values ONLY: ${s.suggestions.join(', ')}.');
      } else if (s.suggestions.isNotEmpty) {
        stages.writeln('   Suggested: ${s.suggestions.join(', ')}.');
      }
    }
    return '''
You are the Project Setup host for the project "$projectName" (${flow.name}).

${flow.intro}

Stages — drive them in order, finishing each before moving on:
$stages
Rules:
- Ask ONE question at a time via `ask_question`; the user picks from options you
  supply (unless a stage is free-form). Selection questions are MULTI-SELECT by
  default — the user may pick several (e.g. multiple platforms, languages,
  frameworks, libraries). Leave `multi` true (the default) for these. Set
  `multi:false` ONLY for a strict single-choice question, such as a yes/no or the
  end-of-stage "continue vs. add more" confirmation. After each answer, your VERY
  NEXT call MUST be `propose_tags` using that stage's `category` — that is how
  answers reach the board (propose one tag per selected value). Never ask two
  questions without a `propose_tags` between.
- ADAPTIVE SCOPE — the interview narrows to the chosen industry. Right AFTER you
  propose `industries`, call `scope_status`. If it reports a sub-axis (e.g.
  Gaming → "Genre"), ask THAT next using the values it returns as the options,
  then `propose_tags` with the reported sub-axis category (e.g. `genre`). Call
  `scope_status` again after `platforms`.
- Before asking `objectives` and `features`, call `scope_options` for that
  category and use the returned values as your question options — they are
  tailored to the selected industry + sub-axis. Do NOT fall back to generic
  options when scoped ones exist.
- PLATFORM-CONDITIONAL STACK — when deriving `languages`/`frameworks`/
  `libraries`, call `scope_options` with the right `platform` for EACH selected
  surface and propose the stack it returns. The correct stack depends on the
  platform: e.g. desktop/console games use C#/C++ engines (Unity/Unreal/Godot),
  mobile games use Flutter/Flame (Dart), web games use TypeScript (Phaser). Never
  propose a desktop/console game in Flutter, or force one language across all
  platforms — honor what `scope_options(platform)` returns per surface.
- END-OF-STAGE CHECK: before advancing a stage, ask the user (via
  `ask_question`) whether they're done with it or want to add/adjust more
  ("Looks good — continue" / "Add more"). Only advance when they choose to
  continue; otherwise keep refining the current stage.
- Use ONLY these `propose_tags` categories: ${tagCategories.join(', ')}.
- ${flow.finalizeGuidance}
- Keep spoken replies to 1-3 sentences. Be concrete and friendly.
''';
  }

  String _refinePrompt() {
    return '''
You are the Project Setup host for "$projectName", now in the REFINE stage. The
plan files already exist as Markdown under /PLANS (an Overview plus one file per
architectural layer, e.g. Client.md, Server.md, Database.md). Your job is to help
the user flesh those plans out with detail, in their own words — this is open
conversation, NOT a multiple-choice interview.

How to work:
- Invite the user to DESCRIBE the project in free text — start with the UI:
  the key screens, layout, look & feel, and what each screen does. Then move to
  backend behavior (API endpoints, business rules), then the data model. Ask one
  open, specific prompt at a time; never give multiple-choice options.
- When the user describes something, decide which plan file it belongs in:
  • UI / screens / look & feel / navigation  → the client/UI layer plan.
  • API / endpoints / services / auth / rules → the server plan.
  • entities / tables / relationships / data  → the database plan.
  • cross-cutting goals / scope / milestones  → Overview.
  Use `list_plans` to see the files if unsure.
- ALWAYS `read_plan` the target file first, then `update_plan` with the FULL new
  Markdown that folds their description into the right section. Preserve the
  existing headings and the `- [ ]` checkbox skeleton — ADD detail and new
  checklist items; never delete what is already there. Edits apply immediately.
- After each edit, tell the user in 1-2 sentences what you added and to which
  plan (e.g. "Added a Dashboard + Settings screen spec to Client.md.").
- When the plans look well fleshed out, let the user know they can keep going or
  click "Done refining" to start turning the plans into tasks. Do not finalize
  anything yourself — the user controls when refinement ends.
- Keep spoken replies short and concrete. Be a collaborative product partner.
''';
  }

  /// Runs one user turn with an internal tool loop. Returns the assistant's
  /// final spoken text. The callbacks surface the live conversation so the UI
  /// can render it inline (mirroring the coordinator chat):
  ///   - [onThinking]      the model's reasoning channel for a round, if any.
  ///   - [onAssistantText] non-empty spoken content the model emits per round.
  ///   - [onToolCall]      a tool the model is about to run (name + args).
  ///   - [onToolResult]    that tool's outcome.
  Future<String> send(
    String userMessage, {
    void Function(String name, String result)? onToolResult,
    void Function(String reasoning)? onThinking,
    void Function(String text)? onAssistantText,
    void Function(String name, Map<String, dynamic> args)? onToolCall,
  }) async {
    // Hard-drop the interview working context at the interview→refine boundary:
    // the plans now exist and the refine stage starts fresh (the transcript is
    // preserved separately for restore).
    if (leanContext && phase == SetupPhase.refine && !_interviewDropped) {
      _history.clear();
      _interviewDropped = true;
    }

    _history.add({'role': 'user', 'content': userMessage});
    _transcript.add({'role': 'user', 'content': userMessage});
    final rollbackTo = _history.length - 1;

    try {
      // Board-state summary (interview only) lets us trim the transcript without
      // the model losing track of what's already chosen — the DB is the truth.
      final stateSummary = (leanContext && phase == SetupPhase.interview)
          ? await executor.setupStateSummary()
          : '';

      // Counts consecutive rounds that produced neither tool calls nor spoken
      // text — a stalled turn. We auto-nudge it back into motion instead of
      // making the user type "?" by hand.
      var emptyRounds = 0;
      for (var round = 0; round < maxToolRounds; round++) {
        // Recompute per round: the system prompt and toolset both depend on the
        // phase, which can flip to refine the moment finalize_setup runs.
        final systemContent = stateSummary.isEmpty
            ? _systemPrompt()
            : '${_systemPrompt()}\n\n$stateSummary';
        final messages = [
          {'role': 'system', 'content': systemContent},
          ...(leanContext ? _recentHistory() : _history),
        ];
        final tools = phase == SetupPhase.refine
            ? SetupTools.buildRefineToolSchemas()
            : SetupTools.buildToolSchemas(categories: tagCategories);

        final resp = await _completeWithRetry(messages, tools);
        final msg = resp.choices.isNotEmpty ? resp.choices.first.message : null;
        final content = msg?.content ?? '';
        final toolCalls = msg?.toolCalls ?? const <ToolCall>[];

        final reasoning = msg?.reasoning;
        if (reasoning != null && reasoning.trim().isNotEmpty) {
          onThinking?.call(reasoning.trim());
        }
        if (content.trim().isNotEmpty) {
          onAssistantText?.call(content.trim());
          _transcript.add({'role': 'assistant', 'content': content.trim()});
        }

        _history.add({
          'role': 'assistant',
          'content': (toolCalls.isNotEmpty && content.isEmpty) ? null : content,
          if (toolCalls.isNotEmpty)
            'tool_calls': [
              for (final t in toolCalls)
                {
                  'id': t.id,
                  'type': 'function',
                  'function': {
                    'name': t.function.name,
                    'arguments': t.function.arguments,
                  },
                }
            ],
        });

        if (toolCalls.isEmpty) {
          // The bounded interview is tool-driven: the host should ALWAYS act via
          // a tool (ask_question / propose_tags / lookup_package / finalize). A
          // turn that ends with NO tool call — whether empty or just narration
          // ("Let me set that up…") — is a stall; auto-nudge it to take the next
          // step, up to twice, so the user never has to type "?" to unstick it.
          // The refine phase is open conversation, so plain-text replies there
          // are legitimate and we don't nudge.
          if (phase == SetupPhase.interview && emptyRounds < 2) {
            emptyRounds++;
            _history.add({'role': 'user', 'content': _continueNudge});
            continue;
          }
          return content;
        }
        emptyRounds = 0;

        for (final call in toolCalls) {
          Map<String, dynamic> args = {};
          try {
            final raw = call.function.arguments.trim();
            if (raw.startsWith('{')) {
              args = (jsonDecode(raw) as Map).cast<String, dynamic>();
            }
          } catch (_) {}

          onToolCall?.call(call.function.name, args);

          final action = _loopGuard.observe(call.function.name, args);
          if (action == LoopAction.block) {
            final note = _loopGuard.feedback(call.function.name, action);
            onToolResult?.call(call.function.name, note);
            _history.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': note,
            });
            continue; // refuse the looping call; model must change course
          }

          final result = await executor.execute(call.function.name, args);
          onToolResult?.call(call.function.name, result);
          // Generating the plans flips the host into the refine stage so the
          // rest of this turn (and the next) uses the plan-editing toolset.
          if (call.function.name == 'finalize_setup') {
            phase = SetupPhase.refine;
          }
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
      if (rollbackTo < _history.length) {
        _history.removeRange(rollbackTo, _history.length);
      }
      rethrow;
    }

    return '';
  }

  /// Calls the model with a bounded retry so a transient inference failure
  /// (dropped socket, 5xx, throttle) self-heals instead of surfacing an error
  /// the user has to manually nudge past. Re-throws only after all attempts.
  Future<ChatCompletionResponse> _completeWithRetry(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await client.createChatCompletion(
          model: _effectiveModel,
          messages: messages,
          tools: tools,
          temperature: 0.6,
          enableThinking: enableThinking,
        );
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
    throw lastError ?? StateError('inference failed');
  }

  /// The recent slice of working [_history] to send: the last
  /// [_historyWindowTurns] user-initiated turns (each with its assistant + tool
  /// messages), sliced at a user-message boundary so tool_call/result pairs stay
  /// intact. Nudges don't count as turns. Older context is carried by the
  /// injected board-state summary, not the raw transcript.
  List<Map<String, dynamic>> _recentHistory() {
    final userIdx = <int>[];
    for (var i = 0; i < _history.length; i++) {
      if (_history[i]['role'] == 'user' &&
          _history[i]['content'] != _continueNudge) {
        userIdx.add(i);
      }
    }
    if (userIdx.length <= _historyWindowTurns) return _history;
    final start = userIdx[userIdx.length - _historyWindowTurns];
    return _history.sublist(start);
  }

  void clearHistory() {
    _history.clear();
    _transcript.clear();
    _interviewDropped = false;
    _loopGuard.reset();
  }

  /// Serialize the transcript (user/assistant text turns) for persistence in
  /// `Projects.setupTranscriptJson`. Sourced from [_transcript], which is
  /// append-only and unaffected by working-context trimming.
  String toTranscriptJson() {
    final turns = _transcript
        .where((m) =>
            (m['content'] is String) && (m['content'] as String).isNotEmpty)
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();
    return jsonEncode(turns);
  }
}
