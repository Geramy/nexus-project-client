// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Renders an AI message as Markdown — headings, lists, **bold**/_italic_,
/// links, tables, and fenced code blocks (monospace) — for the chat surfaces.
/// Wrapped in a [SelectionArea] so the formatted text stays selectable
/// (GptMarkdown produces rich text, which isn't selectable on its own).
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown(this.text, {super.key, this.fontSize = 14, this.color});

  final String text;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.copyWith(
          fontSize: fontSize,
          color: color,
        );
    return SelectionArea(
      child: GptMarkdown(text, style: base),
    );
  }
}
