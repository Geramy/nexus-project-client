// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Step 1 — a short brand intro and the single "Get started" action.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key, required this.onStart});

  final VoidCallback onStart;

  static const _highlights = [
    (Icons.forum_outlined, 'Project Coordinator',
        'Talk or type to an AI that sees your whole project and acts on it.'),
    (Icons.checklist_rtl, 'Plans → tasks',
        'Write a plan and watch it decompose into assignable, trackable work.'),
    (Icons.groups_2_outlined, 'Agent packs',
        'Provision a team of specialized agents tuned to how you work.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Welcome to Nexus Projects',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Gap.xs,
        Text(
          'Your AI-coordinated workspace for planning and shipping real work. '
          'Let’s get you set up in a minute.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: context.nx.textMuted),
        ),
        Gap.xl,
        NexusCard(
          child: Column(
            children: [
              for (final (icon, title, body) in _highlights) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(body, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                if (title != _highlights.last.$2) Gap.md,
              ],
            ],
          ),
        ),
        Gap.xl,
        GradientButton(
          onPressed: onStart,
          label: 'Get started',
          icon: Icons.arrow_forward,
          expand: true,
        ),
      ],
      ),
    );
  }
}
