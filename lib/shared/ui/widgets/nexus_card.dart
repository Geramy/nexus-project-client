// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// The base surface for the redesign: a glassy, hairline-bordered card with a
/// large radius. When [onTap] is provided it becomes hover-aware (border +
/// fill lift on hover) for tactile feedback. Set [glow] for a hero/accent card
/// that casts a colored shadow, or [gradientBorder] for the brand-edge look.
class NexusCard extends StatefulWidget {
  const NexusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.selected = false,
    this.glow = false,
    this.gradientBorder = false,
    this.accent,
    this.radius = AppRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final bool glow;
  final bool gradientBorder;

  /// Optional accent color for glow / selected border. Defaults to primary.
  final Color? accent;
  final double radius;

  @override
  State<NexusCard> createState() => _NexusCardState();
}

class _NexusCardState extends State<NexusCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent ?? scheme.primary;
    final radius = BorderRadius.circular(widget.radius);

    final active = widget.selected || _hover;
    final borderColor = widget.selected
        ? accent.withValues(alpha: 0.7)
        : (_hover ? nx.border : nx.hairline);

    Widget surface = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: active ? nx.glassStrong : nx.glass,
        borderRadius: radius,
        border: widget.gradientBorder
            ? null
            : Border.all(color: borderColor, width: widget.selected ? 1.4 : 1),
        boxShadow: widget.glow
            ? AppShadows.glow(accent, strength: nx.isDark ? 0.28 : 0.18)
            : (active ? AppShadows.card(scheme.shadow) : null),
        gradient: widget.gradientBorder
            ? null
            : (widget.selected
                  ? LinearGradient(
                      colors: [
                        accent.withValues(alpha: nx.isDark ? 0.16 : 0.08),
                        Colors.transparent,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null),
      ),
      // The card paints its own background via the BoxDecoration above. A
      // ListTile/SwitchListTile child paints its background + ink on the nearest
      // Material — which would be the one BEHIND this card, so it'd be hidden
      // (Flutter warns: "ListTile … wrapped in a DecoratedBox that has a
      // background color"). Give the content its own transparent Material so
      // those children render their ink/selection correctly over the card.
      child: Material(
        type: MaterialType.transparency,
        child: widget.child,
      ),
    );

    // Gradient border = paint a 1px brand-gradient ring around a glass fill.
    if (widget.gradientBorder) {
      surface = Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.6),
              scheme.tertiary.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: widget.glow ? AppShadows.glow(accent) : null,
        ),
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius - 1),
          child: surface,
        ),
      );
    }

    if (widget.onTap == null) return surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: surface,
      ),
    );
  }
}
