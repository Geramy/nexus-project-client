// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import 'file_browser_view.dart' show FileEditorPanel;
import 'source_control_panel.dart';
import 'commit_history_panel.dart';

/// The right panel for "Code & Git" — two tabs:
///   - Editor:         viewer/editor for the file selected in the workspace tree.
///   - Source Control: commit form (title + description) + per-file changes list
///                     with stage/discard, plus push.
class CodeAndGitRightPanel extends StatefulWidget {
  const CodeAndGitRightPanel({super.key});

  @override
  State<CodeAndGitRightPanel> createState() => _CodeAndGitRightPanelState();
}

class _CodeAndGitRightPanelState extends State<CodeAndGitRightPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.description_outlined, size: 16),
              height: 40,
              text: 'Editor',
            ),
            Tab(
              icon: Icon(Icons.source_outlined, size: 16),
              height: 40,
              text: 'Source Control',
            ),
            Tab(
              icon: Icon(Icons.history, size: 16),
              height: 40,
              text: 'History',
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              FileEditorPanel(),
              SourceControlPanel(),
              CommitHistoryPanel(),
            ],
          ),
        ),
      ],
    );
  }
}
