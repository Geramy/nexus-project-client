// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Context economy: a single STATELESS LLM call for a focused sub-operation —
/// a fresh, minimal context (one system + one user message), with NO
/// conversation history. Use this whenever a workflow needs the model to do one
/// small, well-defined job (rephrase, split, classify, extract) so the main
/// session isn't burdened with — and billed for — context it doesn't need.
library;

import 'dart:convert';

import 'inference_backend.dart';

/// Run one stateless completion. Returns the assistant text (trimmed), or ''.
Future<String> scopedComplete({
  required InferenceBackend backend,
  required String model,
  required String system,
  required String user,
  int maxTokens = 700,
  double temperature = 0.2,
}) async {
  final resp = await backend.createChatCompletion(
    model: model,
    messages: [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ],
    maxTokens: maxTokens,
    temperature: temperature,
    // Focused sub-ops don't need chain-of-thought; keep the budget for output.
    enableThinking: false,
  );
  if (resp.choices.isEmpty) return '';
  return (resp.choices.first.message.content ?? '').trim();
}

/// Best-effort parse of a JSON array of objects out of model output, tolerating
/// ```json code fences and surrounding prose.
List<Map<String, dynamic>> parseJsonObjectArray(String raw) {
  var s = raw.trim();
  // Strip code fences.
  if (s.startsWith('```')) {
    s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
    final end = s.lastIndexOf('```');
    if (end != -1) s = s.substring(0, end);
  }
  // Narrow to the outermost [ ... ] if there's surrounding text.
  final start = s.indexOf('[');
  final end = s.lastIndexOf(']');
  if (start != -1 && end > start) s = s.substring(start, end + 1);
  try {
    final decoded = jsonDecode(s);
    if (decoded is List) {
      return decoded.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    }
  } catch (_) {}
  return const [];
}
