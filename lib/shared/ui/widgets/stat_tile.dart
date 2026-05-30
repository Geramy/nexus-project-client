// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'nexus_card.dart';

/// A metric tile: a small label over a large value, with an optional icon and
/// trailing delta/caption. Use for usage, spend, counts and headline numbers.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nx = context.nx;
    final accent = this.accent ?? theme.colorScheme.primary;
    return NexusCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: nx.textMuted,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!,
                style: theme.textTheme.bodySmall?.copyWith(color: nx.textFaint)),
          ],
        ],
      ),
    );
  }
}
