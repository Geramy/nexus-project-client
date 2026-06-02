// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_gate.dart';
import '../../core/providers/onboarding_controller.dart';
import 'onboarding_wizard.dart';

/// Precedes [AuthGate]: shows the first-run wizard until onboarding is complete,
/// then hands off to the normal auth gate / workspace. Existing installs are
/// auto-skipped (see [OnboardingController]).
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(onboardingControllerProvider);
    switch (status) {
      case OnboardingStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case OnboardingStatus.needed:
        return const OnboardingWizard();
      case OnboardingStatus.complete:
        return const AuthGate();
    }
  }
}
