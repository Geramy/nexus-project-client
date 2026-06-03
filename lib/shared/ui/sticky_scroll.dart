// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/widgets.dart';

/// Keeps a chat-style scrollable pinned to the bottom as content grows (new
/// messages OR streamed tokens) — the behavior chat UIs are expected to have.
///
/// Auto-stick stays engaged while the view sits at (or within [threshold] of)
/// the bottom. It releases the instant the user scrolls up so they can read
/// history undisturbed, and re-engages the moment they scroll back to the
/// bottom. Wire it once and call [stickToBottom] from `build()`; the
/// scroll-offset listener only fires on real scroll movement (not on pure
/// content-extent growth), so appended content can't prematurely unlock it.
class StickyScrollController {
  StickyScrollController({this.threshold = 48});

  /// Distance from the bottom (px) within which auto-stick is considered
  /// engaged — gives a small "near the bottom" zone for re-locking.
  final double threshold;

  final ScrollController controller = ScrollController();
  bool _stick = true;
  bool _attached = false;

  bool get isStuck => _stick;

  void attach() {
    if (_attached) return;
    _attached = true;
    controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    final pos = controller.position;
    _stick = pos.pixels >= pos.maxScrollExtent - threshold;
  }

  /// Pin to the bottom on the next frame, iff auto-stick is engaged. Safe to
  /// call from `build()` on every rebuild — it's a no-op when already pinned or
  /// when the user has scrolled up.
  void stickToBottom() {
    if (!_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stick || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
    });
  }

  void dispose() {
    controller.removeListener(_onScroll);
    controller.dispose();
  }
}
