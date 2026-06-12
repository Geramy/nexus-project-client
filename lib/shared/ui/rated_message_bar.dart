// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import 'ai_message_rating.dart';

/// Drop-in star-rating row for an AI assistant message that loads + persists the
/// rating itself. Place it beneath any rateable reply; identity is
/// ([conversationId], [messageRef]) so the rating survives reloads and is folded
/// into the Account → Export Tracking JSON.
class RatedMessageBar extends ConsumerStatefulWidget {
  const RatedMessageBar({
    super.key,
    required this.projectId,
    required this.aiKind,
    required this.conversationId,
    required this.messageRef,
  });

  final int projectId;

  /// 'setup' | 'stories' | 'coordinator'.
  final String aiKind;
  final String conversationId;
  final String messageRef;

  @override
  ConsumerState<RatedMessageBar> createState() => _RatedMessageBarState();
}

class _RatedMessageBarState extends ConsumerState<RatedMessageBar> {
  int? _stars;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RatedMessageBar old) {
    super.didUpdateWidget(old);
    if (old.conversationId != widget.conversationId ||
        old.messageRef != widget.messageRef) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final stars = await ref
          .read(nexusDatabaseProvider)
          .getAiRating(widget.conversationId, widget.messageRef);
      if (mounted) setState(() => _stars = stars);
    } catch (_) {
      /* table may not exist yet on a pre-migration DB — show unrated */
    }
  }

  Future<void> _submit(AiRatingResult result) async {
    final reasonsJson = jsonEncode({
      'reasons': result.reasons,
      if (result.other != null) 'other': result.other,
    });
    await ref.read(nexusDatabaseProvider).upsertAiRating(
          projectPk: widget.projectId,
          aiKind: widget.aiKind,
          conversationId: widget.conversationId,
          messageRef: widget.messageRef,
          stars: result.stars,
          reasonsJson: reasonsJson,
        );
    if (mounted) setState(() => _stars = result.stars);
  }

  @override
  Widget build(BuildContext context) {
    return AiMessageRating(stars: _stars, onSubmit: _submit);
  }
}
