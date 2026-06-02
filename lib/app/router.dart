// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:go_router/go_router.dart';
import 'package:nexus_projects_client/features/onboarding/onboarding_gate.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      // OnboardingGate runs the first-run wizard, then hands off to AuthGate.
      builder: (context, state) => const OnboardingGate(),
    ),
    // Future routes for deep linking (tasks, agents, etc.) will go here
  ],
);
