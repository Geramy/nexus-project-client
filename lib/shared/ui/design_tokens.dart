// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Design tokens for the Nexus Projects app — the single source of truth for
/// spacing, corner radius, motion, and elevation. Every screen and widget
/// should pull from these instead of hard-coding magic numbers, so the UI has
/// one consistent rhythm.
///
/// Pair this with [AppTheme] (component theming) and the shared widget kit
/// (NexusCard, SectionHeader, StatusChip, EmptyState, etc.).
library;

import 'package:flutter/material.dart';

/// 4-pt based spacing scale. Use these everywhere instead of raw doubles.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner-radius scale. Buttons/chips use [pill] for the soft, rounded look.
abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;

  /// Effectively a stadium/pill shape for buttons, chips and toggles.
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Animation durations + a default curve for consistent micro-interactions.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}

/// Pre-built [SizedBox] gaps so layouts read as `Gap.lg` instead of
/// `SizedBox(height: 16)`. Use the axis that matches the parent Flex.
abstract final class Gap {
  static const Widget xs = SizedBox(width: AppSpacing.xs, height: AppSpacing.xs);
  static const Widget sm = SizedBox(width: AppSpacing.sm, height: AppSpacing.sm);
  static const Widget md = SizedBox(width: AppSpacing.md, height: AppSpacing.md);
  static const Widget lg = SizedBox(width: AppSpacing.lg, height: AppSpacing.lg);
  static const Widget xl = SizedBox(width: AppSpacing.xl, height: AppSpacing.xl);
  static const Widget xxl =
      SizedBox(width: AppSpacing.xxl, height: AppSpacing.xxl);
}

/// Semantic accessors layered over the active [ColorScheme]. Centralises the
/// "what color means what" decisions so screens don't reach for raw alpha
/// blends. Access via `context.nx`.
extension NexusColors on BuildContext {
  NexusPalette get nx => NexusPalette(Theme.of(this).colorScheme);
}

class NexusPalette {
  const NexusPalette(this.scheme);
  final ColorScheme scheme;

  bool get isDark => scheme.brightness == Brightness.dark;

  /// A subtle hairline border used on cards, dividers and inputs.
  Color get hairline => scheme.outlineVariant;

  /// Stronger border for focus/hover affordances.
  Color get border => scheme.outline;

  /// Muted text for secondary labels / helper copy.
  Color get textMuted => scheme.onSurfaceVariant;

  /// Faint text for timestamps / metadata.
  Color get textFaint => scheme.onSurfaceVariant.withValues(alpha: 0.65);

  /// Translucent fill for raised surfaces (cards, tiles) — glassy on dark,
  /// soft tint on light.
  Color get glass => isDark
      ? Colors.white.withValues(alpha: 0.05)
      : scheme.surfaceContainerHighest.withValues(alpha: 0.6);

  /// A slightly stronger glass for hovered / selected surfaces.
  Color get glassStrong => isDark
      ? Colors.white.withValues(alpha: 0.09)
      : scheme.surfaceContainerHighest;

  // ── Semantic status colors ──────────────────────────────────────────────
  Color get success => const Color(0xFF34D399);
  Color get warning => const Color(0xFFF59E0B);
  Color get danger => scheme.error;
  Color get info => scheme.tertiary;

  /// Tint a status color for use as a chip / banner background.
  Color tintOf(Color c) => c.withValues(alpha: isDark ? 0.18 : 0.12);
}

/// Scheme-aware gradients so widgets don't need to import the theme. The
/// canonical brand gradient lives on [AppTheme]; these derive from the active
/// [ColorScheme] so they adapt per theme.
abstract final class AppGradients {
  static LinearGradient accent(ColorScheme s) => LinearGradient(
        colors: [s.primary, s.tertiary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient subtle(ColorScheme s) => LinearGradient(
        colors: [
          s.primary.withValues(alpha: 0.18),
          s.tertiary.withValues(alpha: 0.10),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// Soft elevation shadows tuned for the dark Nebula backdrop (and reused, more
/// subtly, on the light theme). Avoid Material's default harsh drop shadows.
abstract final class AppShadows {
  static List<BoxShadow> card(Color tint) => [
        BoxShadow(
          color: tint.withValues(alpha: 0.18),
          blurRadius: 24,
          spreadRadius: -6,
          offset: const Offset(0, 10),
        ),
      ];

  /// A colored glow used behind accent surfaces / hero cards.
  static List<BoxShadow> glow(Color color, {double strength = 0.35}) => [
        BoxShadow(
          color: color.withValues(alpha: strength),
          blurRadius: 32,
          spreadRadius: -8,
          offset: const Offset(0, 8),
        ),
      ];
}
