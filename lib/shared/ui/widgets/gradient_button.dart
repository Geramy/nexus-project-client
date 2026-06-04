// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../design_tokens.dart';

/// A pill-shaped primary button painted with the signature brand gradient.
/// Use for the single most important action on a surface (e.g. "New Persona",
/// "Talk to Coordinator", "Sign in"). For secondary actions use the themed
/// [FilledButton] / [OutlinedButton], which are already pill-shaped.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.busy = false,
    this.expand = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final radius = BorderRadius.circular(AppRadius.pill);

    // The label, made shrink-safe: one line, ellipsized rather than overflowing.
    Widget labelText() => Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );

    // Use LayoutBuilder so the label can flex (and ellipsize) ONLY when this
    // button is given bounded width (e.g. inside an Expanded / full-width slot /
    // narrow screen). Under unbounded constraints (a Wrap or min-size Row) a
    // flexible child would crash RenderFlex, so we fall back to intrinsic size.
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedWidth;
        final lbl = bounded ? Flexible(child: labelText()) : labelText();
        return Row(
          mainAxisSize: (widget.expand || bounded)
              ? MainAxisSize.max
              : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else if (widget.icon != null)
              Icon(widget.icon, size: 18, color: Colors.white),
            if ((widget.icon != null || widget.busy))
              const SizedBox(width: AppSpacing.sm),
            lbl,
          ],
        );
      },
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: enabled ? 1 : 0.5,
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: radius,
              boxShadow: enabled && _hover
                  ? AppShadows.glow(AppTheme.brandViolet, strength: 0.45)
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
