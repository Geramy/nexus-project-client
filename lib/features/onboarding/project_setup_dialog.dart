// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'steps/project_step.dart';
import '../../core/providers/app_shell_provider.dart';
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
                  // Land on the project workspace so the setup wizard auto-opens
                  // for the new (notStarted) project — otherwise the user is left
                  // on whatever view they were on (e.g. Launch) and has to open
                  // setup by hand.
                  ProviderScope.containerOf(ctx, listen: false)
                      .read(currentMainViewProvider.notifier)
                      .setView(MainView.projectPlans);
                  Navigator.of(ctx).pop();
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
