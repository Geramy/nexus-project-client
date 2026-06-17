// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the orchestrator captures each worker (generalist) agent's full
/// tool-call trace to the DB for export — PERSISTED, default OFF.
///
/// It's a lot of data (every file read/edit/commit, per task), so it's opt-in:
/// flip it on in Account → Export Tracking when you want to debug worker tool
/// calls, run the workers, then "Export worker tool calls". Off = nothing is
/// written, so it never accumulates when you're not looking.
///
/// Hand-written (no codegen) so it builds without running build_runner.
class WorkerCaptureNotifier extends Notifier<bool> {
  static const _prefsKey = 'worker_capture_enabled';

  @override
  bool build() {
    _hydrate();
    return false; // default OFF
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey) ?? false;
    if (!ref.mounted) return; // provider disposed during the await (riverpod 3)
    if (saved != state) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

final workerCaptureProvider = NotifierProvider<WorkerCaptureNotifier, bool>(
  WorkerCaptureNotifier.new,
);
