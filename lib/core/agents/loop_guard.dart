// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

/// What the harness should do with a tool call the [LoopGuard] just observed.
enum LoopAction {
  /// Novel or low-repeat call — run it normally.
  proceed,

  /// Seen this exact call recently. Run it, but feed the model a note so it can
  /// self-correct ("you already did this — try something different").
  warn,

  /// Repeated past the limit. Do NOT run it; force the model off this path.
  block,
}

/// Detects unproductive repetition in an agent's tool-calling loop.
///
/// Implements the structural + progressive-intervention technique that
/// production agent harnesses converge on (e.g. NousResearch's Tool-Call Loop
/// Guard, the DebounceHook pattern): each tool call is fingerprinted as
/// `tool + canonical(args)` and counted within a sliding window. A recurring
/// fingerprint escalates proceed → warn → block instead of hard-killing on the
/// first repeat, so the model gets a chance to correct itself before the call
/// is refused. A hard round cap in the harness remains the final backstop.
///
/// Detection is purely structural (identical tool + arguments) — it does not
/// embed outputs, so it has no model/latency cost. It deliberately does not try
/// to catch semantically-rephrased loops; that needs an embedding signal and is
/// out of scope here.
///
/// Reusable across harnesses: each session/turn holds its own instance.
class LoopGuard {
  LoopGuard({this.warnAt = 2, this.blockAt = 3, this.window = 12})
      : assert(warnAt >= 1, 'warnAt must be >= 1'),
        assert(blockAt >= warnAt, 'blockAt must be >= warnAt'),
        assert(window >= blockAt, 'window must be >= blockAt');

  /// Repeat count (inclusive) at which a call earns a warning.
  final int warnAt;

  /// Repeat count (inclusive) at which a call is blocked outright.
  final int blockAt;

  /// How many of the most-recent fingerprints to retain when counting repeats.
  final int window;

  final List<String> _recent = [];

  /// Record a tool call that is about to run and decide what the harness should
  /// do with it. Call this once per tool call, in order.
  LoopAction observe(String tool, Map<String, dynamic> args) {
    final fp = _fingerprint(tool, args);
    _recent.add(fp);
    if (_recent.length > window) _recent.removeAt(0);
    final count = _recent.where((f) => f == fp).length;
    if (count >= blockAt) return LoopAction.block;
    if (count >= warnAt) return LoopAction.warn;
    return LoopAction.proceed;
  }

  /// A short note to feed back to the model (as a tool result) on [warn] or
  /// [block], explaining why so it changes course. Empty for [proceed].
  String feedback(String tool, LoopAction action) => switch (action) {
        LoopAction.warn =>
          'Loop guard: you already called `$tool` with these exact arguments and '
              'got the same result. Do not repeat it — take a different action or '
              'finish your reply.',
        LoopAction.block =>
          'Loop guard: `$tool` was called repeatedly with identical arguments and '
              'is stuck in a loop, so this call was NOT executed. Choose a '
              'different action or finalize now.',
        LoopAction.proceed => '',
      };

  /// Forget all history (e.g. when a session's conversation is cleared).
  void reset() => _recent.clear();

  static String _fingerprint(String tool, Map<String, dynamic> args) =>
      '$tool(${_canonical(args)})';

  /// Deterministic, key-order-independent serialization so logically-identical
  /// argument maps produce the same fingerprint regardless of key ordering.
  static String _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '$k:${_canonical(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canonical).join(',')}]';
    return jsonEncode(v);
  }
}
