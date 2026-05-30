// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Semantic intent for a [StatusChip] — drives its color.
enum ChipIntent { neutral, info, success, warning, danger, accent }

/// A compact pill label for statuses, priorities, modes and tags. Replaces the
/// app's many one-off `Container` chips with a single rounded, tinted shape.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.intent = ChipIntent.neutral,
    this.icon,
    this.filled = false,
    this.dense = false,
  });

  final String label;
  final ChipIntent intent;
  final IconData? icon;

  /// When true the chip uses a solid tint; otherwise a soft outlined tint.
  final bool filled;
  final bool dense;

  Color _color(BuildContext context) {
    final nx = context.nx;
    return switch (intent) {
      ChipIntent.neutral => nx.textMuted,
      ChipIntent.info => nx.info,
      ChipIntent.success => nx.success,
      ChipIntent.warning => nx.warning,
      ChipIntent.danger => nx.danger,
      ChipIntent.accent => Theme.of(context).colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final bg = color.withValues(alpha: filled ? 0.9 : (context.nx.isDark ? 0.16 : 0.12));
    final fg = filled ? Colors.white : color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 3 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: dense ? 10.5 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
