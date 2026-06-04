// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A consistent section / page header: an optional gradient accent bar, a
/// title, optional subtitle, and an optional trailing action area. Use at the
/// top of panels and as group dividers inside forms.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.accent = true,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  /// Show the gradient accent bar to the left of the title.
  final bool accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nx = context.nx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (accent) ...[
          Container(
            width: 4,
            height: dense ? 18 : 26,
            decoration: BoxDecoration(
              gradient: AppGradients.accent(theme.colorScheme),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        if (icon != null) ...[
          Icon(icon, size: dense ? 18 : 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style:
                    (dense
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: nx.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}
