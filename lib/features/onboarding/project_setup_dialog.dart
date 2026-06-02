// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import 'steps/project_step.dart';
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
                  AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xl),
              child: ProjectStep(
                headline: 'New project',
                subhead:
                    'Name it and choose the project type. You can change both later.',
                defaultName: 'New Project',
                onCreated: () => Navigator.of(ctx).pop(),
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
