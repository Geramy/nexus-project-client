// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:go_router/go_router.dart';
import 'package:nexus_projects_client/app/auth_gate.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthGate(),
    ),
    // Future routes for deep linking (tasks, agents, etc.) will go here
  ],
);
