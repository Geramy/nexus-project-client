// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Center-pane workspace for the IVR / Call Systems project type. The visual
/// call-flow canvas + PBX entity editors are built in Phase 4; this is the
/// mounting point reached via the gated `Call Flow` nav item.
class CallFlowWorkspace extends StatelessWidget {
  const CallFlowWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.account_tree_outlined,
      title: 'Call Flow',
      message:
          'Design menus, routing, voicemail, and AI voicebots here. (Builder canvas coming in Phase 4.)',
    );
  }
}
