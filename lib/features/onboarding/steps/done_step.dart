// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Step 5 — confirmation. Finishing marks onboarding complete and hands off to
/// the workspace.
class DoneStep extends StatelessWidget {
  const DoneStep({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.celebration_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          Gap.md,
          Text(
            "You're all set",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Gap.xs,
          Text(
            'Your project and agents are ready. Open the workspace and start a '
            'conversation with your Coordinator.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.nx.textMuted,
            ),
          ),
          Gap.xl,
          GradientButton(
            onPressed: onFinish,
            label: 'Enter workspace',
            icon: Icons.arrow_forward,
            expand: true,
          ),
        ],
      ),
    );
  }
}
