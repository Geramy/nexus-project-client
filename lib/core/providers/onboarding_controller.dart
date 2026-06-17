// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_provider.dart';

/// Whether the first-run onboarding wizard still needs to run.
///   - [loading]  — reading the saved flag / probing existing data.
///   - [needed]   — show the wizard.
///   - [complete] — hand off to the normal app.
enum OnboardingStatus { loading, needed, complete }

/// Tracks (and persists) whether first-run onboarding is complete.
///
/// On first build it hydrates the saved flag. If unset, it auto-skips the wizard
/// for EXISTING installs — anyone who already has a project or extra client (see
/// [NexusDatabase.hasExistingUserContent]) — so current users aren't interrupted
/// by a wizard they don't need. A truly fresh install lands in [needed].
class OnboardingController extends StateNotifier<OnboardingStatus> {
  OnboardingController(this.ref) : super(OnboardingStatus.loading) {
    _hydrate();
  }

  final Ref ref;
  static const _prefsKey = 'onboarding_complete';

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) ?? false) {
      state = OnboardingStatus.complete;
      return;
    }
    // No saved flag: auto-skip for installs that already have user content, and
    // persist so the probe only happens once.
    try {
      final db = ref.read(nexusDatabaseProvider);
      if (await db.hasExistingUserContent()) {
        await prefs.setBool(_prefsKey, true);
        state = OnboardingStatus.complete;
        return;
      }
    } catch (_) {
      // If the probe fails, fall through to showing the wizard rather than
      // wrongly skipping it.
    }
    state = OnboardingStatus.needed;
  }

  /// Mark onboarding finished and persist it, then hand off to the app.
  Future<void> markComplete() async {
    state = OnboardingStatus.complete;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }
}

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingStatus>(
      (ref) => OnboardingController(ref),
    );
