// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a multiline text composer so a bare **Enter** submits the message and
/// **Shift+Enter** inserts a newline (the conventional chat behavior).
///
/// Wrap the composer's [TextField] (which should be multiline — `maxLines` > 1
/// or `null` — so the Shift+Enter newline is actually visible). Don't also pass
/// `onSubmitted` to that field: on a multiline field Enter never fires it, and
/// on a single-line field it would double-send. This intercepts the key first.
class SubmitOnEnter extends StatelessWidget {
  const SubmitOnEnter({
    super.key,
    required this.onSubmit,
    required this.child,
    this.enabled = true,
  });

  /// Called when Enter (without Shift) is pressed.
  final VoidCallback onSubmit;

  /// The composer to wrap — typically a [TextField].
  final Widget child;

  /// When false, Enter is left alone (e.g. while a send is in flight).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Focus(
      // CRITICAL: this wrapper must NEVER hold primary focus itself — it only
      // observes key events bubbling up from the focused TextField below it.
      // With the default (focusable) Focus, Tab traversal or a rebuild could
      // park focus on THIS node instead of the field; then letters bubble to
      // onKeyEvent (returned `ignored`) while the EditableText never sees them —
      // a "dead keyboard" until you click the field. canRequestFocus:false +
      // skipTraversal:true keep it a pure key-observer, so onKeyEvent still
      // fires (events bubble up from the focused field) but focus can't land here.
      canRequestFocus: false,
      skipTraversal: true,
      // Intercept before the TextField's own handler. KeyDownEvent only (not
      // repeats) so a held Enter sends once.
      onKeyEvent: (node, event) {
        if (!enabled) return KeyEventResult.ignored;
        final isEnter =
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter;
        if (event is KeyDownEvent &&
            isEnter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          onSubmit();
          return KeyEventResult.handled;
        }
        // Let Shift+Enter (and everything else) fall through to the field, where
        // it inserts a newline as normal.
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
