// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'steps/project_step.dart';
import '../../core/providers/app_shell_provider.dart';
import '../../features/project_setup/project_setup_wizard.dart';
import '../../shared/ui/nexus_ui.dart';

/// Presents the SAME project-setup screen the onboarding wizard uses (name +
/// agent-pack selection, running the same create + provision workflow) as a
/// dialog — so the in-app "New Project" action reuses that flow instead of
/// duplicating a separate screen.
Future<void> showProjectSetupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: ProjectStep(
                headline: 'New project',
                subhead:
                    'Name it and choose the project type. You can change both later.',
                defaultName: 'New Project',
                onCreated: () {
                  // Land on the project workspace AND open the setup wizard for
                  // the just-created project. We open it directly (not relying on
                  // the workspace's auto-open heuristic) so it ALWAYS appears
                  // instead of leaving the user on their previous view (e.g.
                  // Launch). showProjectSetupWizard is idempotent, so the
                  // workspace auto-open can't stack a second one.
                  final container = ProviderScope.containerOf(
                    context,
                    listen: false,
                  );
                  container
                      .read(currentMainViewProvider.notifier)
                      .setView(MainView.projectPlans);
                  final projectId = container.read(currentProjectIdProvider);
                  final clientId = container.read(currentClientIdProvider);
                  Navigator.of(ctx).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      showProjectSetupWizard(context, projectId, clientId);
                    }
                  });
                },
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
