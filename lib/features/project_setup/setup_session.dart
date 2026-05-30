// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import '../../core/agents/loop_guard.dart';
import '../../infrastructure/inference/inference_backend.dart';
import 'setup_tools.dart';

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
    this.maxToolRounds = 40,
  });

  final InferenceBackend client;
  final String model;
  final String projectName;
  final SetupToolExecutor executor;
  final int maxToolRounds;

  final List<Map<String, dynamic>> _history = [];

  /// Detects when the interview agent gets stuck re-issuing the same tool call
  /// (e.g. re-asking the same question or re-proposing the same tags). Lives at
  /// session scope so it catches loops that span user turns, not just one turn.
  final LoopGuard _loopGuard = LoopGuard();

  List<Map<String, dynamic>> get history => List.unmodifiable(_history);

  String get _effectiveModel =>
      model.trim().isEmpty ? 'default-coordinator' : model.trim();

  String _systemPrompt() {
    return '''
You are the Project Setup host for the project "$projectName". Your job is to
interview the user with SHORT, BOUNDED questions and build a structured project
profile of tags across seven sections: Applicable Industries, Platforms,
Objectives, Features, Languages, Frameworks, Libraries.

Rules:
- Ask ONE question at a time via the `ask_question` tool. The user answers by
  picking options you supply — never expect free text.
- MANDATORY LOOP for every question you ask: after the user answers (the tool
  result will say "User selected: …"), your VERY NEXT tool call MUST be
  `propose_tags` for that answer, before you ask anything else. Never ask two
  questions in a row without a `propose_tags` between them. If the user
  skipped, you may skip the propose for that question only. This is how tags
  reach the board — if you forget, the user sees questions but no tags.
- Drive the interview in this fixed order, finishing each stage before moving
  on: Industries → Platforms → Objectives → Features → Libraries.
  • Features (second-to-last) are the concrete capabilities the app must ship
    (e.g. "client portal", "geofencing", "invoicing"); propose them as
    `features` tags.
  • Libraries are the LAST stage: only after features are settled, suggest
    specific packages that implement them (each verified via `lookup_package`).
    For EACH library, set `forLanguage` to the language it's used with (e.g. a
    pub.dev package → "Dart", a NuGet package → "C#") using only allowed
    Languages values, so it attaches to the right side of the stack.
  Keep it to a handful of questions per stage; do not interrogate.
- NEVER ask the user about programming languages or frameworks — not as a
  question, not as options, not even to confirm. The stack is chosen
  AUTOMATICALLY from the industries, platforms, objectives, and features. You
  derive and propose it yourself (as `languages`/`frameworks` tags right after
  features); you do not interview for it. The deterministic resolver finalizes
  it. Default stack you apply unless the features clearly demand otherwise:
  • Any UI / client surface → Flutter + Dart.
  • Server / API tier → C# / ASP.NET Core + Entity Framework Core.
  • Database → PostgreSQL.
  • Only deviate for hard requirements: heavy computation / highly distributed
    / ML → C/C++ (Drogon) API tier; memory-safety-critical → Rust (last
    resort). When unsure, use the default above — do NOT ask.
- Before proposing ANY library, call `lookup_package` and only propose it if it
  is not dead/archived. Prefer trusted orgs (flutter, dart-lang, google,
  facebook/meta, etc.).
- Tags are saved as `proposed` for the user to accept/reject — say so when you
  spend a spoken turn on it. Languages and platforms must use allowed values
  only (the `propose_tags` tool will silently drop off-vocab values).
- When the user is satisfied, call `finalize_setup` to generate the plan files.
- Keep spoken replies to 1-3 sentences. Be concrete and friendly.
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
    _history.add({'role': 'user', 'content': userMessage});
    final rollbackTo = _history.length - 1;
    final tools = SetupTools.buildToolSchemas();

    try {
      for (var round = 0; round < maxToolRounds; round++) {
        final messages = [
          {'role': 'system', 'content': _systemPrompt()},
          ..._history,
        ];

        final resp = await client.createChatCompletion(
          model: _effectiveModel,
          messages: messages,
          tools: tools,
          temperature: 0.6,
          enableThinking: true,
        );
        final msg = resp.choices.isNotEmpty ? resp.choices.first.message : null;
        final content = msg?.content ?? '';
        final toolCalls = msg?.toolCalls ?? const <ToolCall>[];

        final reasoning = msg?.reasoning;
        if (reasoning != null && reasoning.trim().isNotEmpty) {
          onThinking?.call(reasoning.trim());
        }
        if (content.trim().isNotEmpty) {
          onAssistantText?.call(content.trim());
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

        if (toolCalls.isEmpty) return content;

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

  void clearHistory() {
    _history.clear();
    _loopGuard.reset();
  }

  /// Serialize the transcript (user/assistant text turns) for persistence in
  /// `Projects.setupTranscriptJson`.
  String toTranscriptJson() {
    final turns = _history
        .where((m) =>
            (m['role'] == 'user' || m['role'] == 'assistant') &&
            (m['content'] is String) &&
            (m['content'] as String).isNotEmpty)
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();
    return jsonEncode(turns);
  }
}
