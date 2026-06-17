// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_skipped_provider.g.dart';

/// Whether the user chose "Skip for now" on the login screen — PERSISTED in
/// SharedPreferences so we don't prompt them to sign in on every launch.
///
/// Returns false by default and hydrates the saved value asynchronously, the
/// same sync-default + async-hydrate pattern as [AppThemeNotifier]. Signing in
/// or signing out is unaffected; this only suppresses the login wall.
@riverpod
class AuthSkippedNotifier extends _$AuthSkippedNotifier {
  static const _prefsKey = 'auth_skipped';

  @override
  bool build() {
    _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey) ?? false;
    if (!ref.mounted) return; // provider disposed during the await (riverpod 3)
    if (saved != state) state = saved;
  }

  /// Record + persist that the user skipped sign-in.
  Future<void> skip() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}
