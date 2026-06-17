// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'lean_context_provider.g.dart';

/// Whether "Lean context" mode is on — PERSISTED in SharedPreferences.
///
/// When ON (default), the AI flows reconstruct state from the harness (the DB)
/// instead of replaying full conversations:
///   - the Setup interview sends a board-state summary + a short rolling window
///     of turns instead of the whole transcript, and drops the interview context
///     entirely once plans are finalized;
///   - the Coordinator exposes only its core task/plan tools by default and pulls
///     in file/git/CI tool groups on demand via `request_tools`.
///
/// When OFF, both flows fall back to the previous behavior (full history, all
/// tools every call). Toggle it in Account → Lean context to compare.
@riverpod
class LeanContextNotifier extends _$LeanContextNotifier {
  static const _prefsKey = 'lean_context_enabled';

  @override
  bool build() {
    _hydrate();
    return true; // default ON
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey) ?? true;
    if (!ref.mounted) return; // provider disposed during the await (riverpod 3)
    if (saved != state) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}
