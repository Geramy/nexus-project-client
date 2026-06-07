// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../../core/agents/loop_guard.dart';
import '../../infrastructure/inference/inference_backend.dart';
import '../../infrastructure/lemonade/services/persona_model_resolver.dart'
    show kDefaultOmniCollection;
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
    this.maxToolRounds = 12,
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

  /// Set by [cancel] to abort the current turn between rounds (the user tapped
  /// the thinking indicator because it looped/hung). Reset at the start of [send].
  bool _cancelled = false;

  /// Abort the in-flight turn after the current model round returns.
  void cancel() => _cancelled = true;

  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  String get _effectiveModel =>
      model.trim().isEmpty ? kDefaultOmniCollection : model.trim();

  String _systemPrompt() =>
      phase == SetupPhase.refine ? _refinePrompt() : _interviewPrompt();

  /// Categories the active flow proposes into (its stage keys) — drives the
  /// `propose_tags` schema so each project type proposes its own sections.
  List<String> get tagCategories => flow.stages.map((s) => s.key).toList();

  String _interviewPrompt() {
    final steps = StringBuffer();
    var n = 1;
    for (final s in flow.stages) {
      final opts = s.suggestions.isEmpty
          ? ' Offer a few relevant options.'
          : (s.vocab == SetupVocab.closed
                ? ' Offer ONLY these options: ${s.suggestions.join(', ')}.'
                : ' Suggested options: ${s.suggestions.join(', ')}.');
      steps.writeln(
        '$n. ${s.title} — ask about ${s.guidance.trim()}'
        '${s.required ? '' : ' (optional — skip if it does not apply)'}'
        ' [category: `${s.key}`]$opts',
      );
      n++;
    }
    final stepCount = flow.stages.length;
    return '''
You are the Setup host for "$projectName" (${flow.name}). Your job is to build the project profile by TAGGING it. Keep every reply to 1-2 short sentences.

${flow.intro}

You have $stepCount topics to fill (listed below). Tag what the user already told you FIRST, then ask about whatever is still open — one at a time, in flexible order.

$steps
START FROM WHAT THEY SAID:
- Read the user's description and FIRST call `propose_tags` for everything it already implies, mapping their words to the closest option for each topic. Reasonable inferences are welcome — e.g. "a mobile app for a lemonade stand where users find and order" → propose_tags([{category:"industries", value:"Food & Beverage"}, {category:"platforms", value:"iOS"}, {category:"platforms", value:"Android"}, {category:"objectives", value:"Ordering"}, {category:"objectives", value:"Store locator"}]).
- Then reflect back in one short sentence what you recorded.

HOW TO ASK (for the topics still open):
- Each remaining question goes through the `ask_question` tool — it shows the options as buttons the user taps, so calling it is how you get their answer.
- Put any progress label inside the tool call, e.g. ask_question(question: "Objectives — anything else it should do?", options: ["…","…"], multi: true).

FOR EACH REMAINING TOPIC (one the description did not already answer):
1. Call the `ask_question` tool with the question + its options (multi-select unless it is a yes/no).
2. Right after the user answers, call `propose_tags` to save their picks under that topic's `category`, then continue.
3. Move to the next open topic.

RULES:
- Base every tag on what the user picked or said. Use the `category` shown in each question's brackets.
- Each tag VALUE is a SHORT label — a few words (≤5), one idea per tag. Give several items as several tags. Example: "track orders and notify users" → propose_tags([{category:"objectives", value:"Order tracking"}, {category:"objectives", value:"User notifications"}]).
- If a tool result says "NEXT: …", do that next (some answers unlock a follow-up question, e.g. Industry → Genre).
- STACK: once platforms are known, also `propose_tags` at least one `languages` and one `frameworks` value yourself (minimal, fitting the platforms) — the user usually will not mention these.
- When every required question has at least one tag (${_requiredTitles()}), call `finalize_setup`. It refuses and lists what is missing if you call it too early.
- ${flow.finalizeGuidance}
''';
  }

  /// Titles of the flow's required stages, for the "fill these before finalize"
  /// line in the interview prompt (mirrors the executor's hard gate).
  String _requiredTitles() =>
      flow.stages.where((s) => s.required).map((s) => s.title).join(', ');

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
    _cancelled = false;
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
      // text — a true stall. We auto-nudge those back into motion. A spoken
      // reply with no tool is a legitimate conversational turn and is NOT a stall.
      var emptyRounds = 0;
      // Bounds how many times per turn we force the model to reconcile a
      // looked-up-but-undecided package before letting the turn end (the pending
      // state persists to the next turn and still blocks finalize, so nothing
      // slips through — this only prevents an in-turn infinite loop).
      var reconcileRounds = 0;
      // Bounds how many times per turn we force the model to RECORD a selection
      // the user just made via ask_question but the model only acknowledged
      // (the common "picked some features → model says 'great!' → stops without
      // propose_tags" stall that leaves a required section empty).
      var selectionNudges = 0;
      // Bounds how many times per turn we push the model to re-ask via the
      // ask_question TOOL after it typed a question (with options) as a plain
      // message — which renders no buttons, so the user can't answer.
      var askToolNudges = 0;
      for (var round = 0; round < maxToolRounds; round++) {
        // The user tapped "stop" — abort before issuing another model round.
        if (_cancelled) return '';
        // The system prompt is kept STATIC (phase-only) and the tool list is
        // deterministic, so the [system + tools] prefix is byte-identical every
        // round and across turns — which is exactly what llama.cpp/Lemonade
        // prefix-caching reuses. The volatile board state is appended at the TAIL
        // (after history) so it never invalidates that cached prefix.
        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': _systemPrompt()},
          ...(leanContext ? _recentHistory() : _history),
          if (stateSummary.isNotEmpty)
            {'role': 'system', 'content': stateSummary},
        ];
        final tools = phase == SetupPhase.refine
            ? SetupTools.buildRefineToolSchemas()
            : SetupTools.buildToolSchemas(
                categories: tagCategories,
                includeLibraryTools: true,
              );

        final resp = await _completeWithRetry(messages, tools);
        // The user tapped "stop" WHILE this round's (blocking) generation was in
        // flight. Discard its output entirely — don't speak the text, record it,
        // or execute its tools — so a runaway/looping answer is genuinely cut
        // short instead of applying one last full round of effects.
        if (_cancelled) return '';
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
                },
            ],
        });

        if (toolCalls.isEmpty) {
          // A SPOKEN reply with no tool is a normal conversational turn now (an
          // open question or a reaction) — hand it back to the user. Only a truly
          // EMPTY round (no text AND no tool) is a stall worth auto-nudging, so
          // the user never has to type "?" to unstick a silent model.
          final spoke = content.trim().isNotEmpty;
          if (!spoke && phase == SetupPhase.interview && emptyRounds < 2) {
            emptyRounds++;
            _history.add({'role': 'user', 'content': _continueNudge});
            continue;
          }
          // ANTI-STALL: the user just answered an ask_question but the model is
          // about to end the turn without recording it (no propose_tags). That's
          // the "picked features → model acknowledged → stopped" stall that
          // leaves a required section empty and the Generate-plan button stuck.
          // Poke it to save the selection before stopping.
          if (phase == SetupPhase.interview &&
              executor.lastSelection != null &&
              selectionNudges < 2) {
            selectionNudges++;
            final sel = executor.lastSelection!;
            executor.lastSelection = null;
            _history.add({
              'role': 'user',
              'content':
                  'You have NOT recorded the user\'s last answer ($sel). Call '
                  'propose_tags NOW to save those under the matching category, '
                  'then continue with the next topic — do not stop until their '
                  'selections are on the board.',
            });
            continue;
          }
          // ANTI-PROSE-QUESTION: the model wrote a question (with options) as a
          // chat message instead of calling ask_question, so NO selectable
          // buttons rendered and the user cannot answer. Force it through the
          // tool. The tells below ("Options:", "select all", "(select…") are
          // what the model emits when it simulates the picker in prose.
          final low = content.toLowerCase();
          final looksLikeProseQuestion =
              low.contains('options:') ||
              low.contains('select all') ||
              low.contains('(you may select') ||
              low.contains('(select');
          if (phase == SetupPhase.interview &&
              looksLikeProseQuestion &&
              askToolNudges < 2) {
            askToolNudges++;
            _history.add({
              'role': 'user',
              'content':
                  'To collect the user\'s answer, ask that question with the '
                  '`ask_question` tool now (question + options, multi:true) — it '
                  'shows tappable buttons the user can answer.',
            });
            continue;
          }
          // GUARD (we are the hand-holder, not the model): never let a turn end
          // with an item the host looked up or was weighing left undecided. Every
          // lookup_package / consider_items option must resolve to an add
          // (propose_tags) or an explicit skip (dismiss_item). If any dangle,
          // force the model to reconcile them now — that's how an announced
          // "let me think about these…" silently produced nothing.
          if (phase == SetupPhase.interview && reconcileRounds < 2) {
            final pending = executor.pendingDecisions;
            if (pending.isNotEmpty) {
              reconcileRounds++;
              _history.add({
                'role': 'user',
                'content':
                    'Before you stop: you were weighing ${pending.join(', ')} '
                    'but have not decided on ${pending.length == 1 ? 'it' : 'them'}. '
                    'For EACH, either call propose_tags to add it or dismiss_item '
                    'to skip it with a reason. If you are unsure which to keep, '
                    'ask the user with ask_question first.',
              });
              continue;
            }
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

          // A tool that THROWS (network drop, registry 5xx, a DB upsert error in
          // propose_tags) must NOT abort the whole turn — that's how an announced
          // action ("let me check a few libraries…") silently produced nothing.
          // Surface the failure to the model as this tool's result with an
          // explicit retry instruction so it self-corrects within the remaining
          // rounds; the LoopGuard still bounds a tool that keeps failing.
          String result;
          var threw = false;
          try {
            result = await executor.execute(call.function.name, args);
          } catch (e) {
            threw = true;
            result =
                'ERROR: ${call.function.name} failed and did NOT take effect: '
                '$e. Retry this tool once now (or take a different step) — do '
                'not tell the user it succeeded.';
          }
          onToolResult?.call(call.function.name, result);
          // Generating the plans flips the host into the refine stage so the
          // rest of this turn (and the next) uses the plan-editing toolset —
          // but ONLY when finalize actually succeeded.
          if (!threw && call.function.name == 'finalize_setup') {
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
          // Ask the server (llama.cpp / Lemonade) to reuse the KV cache for the
          // identical [system + tools] prefix we now hold stable across rounds
          // and turns. Harmless on backends that ignore it.
          extra: const {'cache_prompt': true},
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
        .where(
          (m) =>
              (m['content'] is String) && (m['content'] as String).isNotEmpty,
        )
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();
    return jsonEncode(turns);
  }
}
