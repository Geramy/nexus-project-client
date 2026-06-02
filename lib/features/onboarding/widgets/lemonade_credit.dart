// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../../infrastructure/nexus/nexus_url_launcher.dart';
import '../../../shared/ui/nexus_ui.dart';

/// "Backend powered by Lemonade" attribution with a link to the Lemonade GitHub.
/// Lemonade is the open multi-modal inference server Nexus is built to run on.
class LemonadeCredit extends StatelessWidget {
  const LemonadeCredit({super.key});

  static const lemonadeGithubUrl = 'https://github.com/lemonade-sdk/lemonade';

  @override
  Widget build(BuildContext context) {
    final muted = context.nx.textMuted;
    return Tooltip(
      message: lemonadeGithubUrl,
      child: InkWell(
        borderRadius: AppRadius.smAll,
        onTap: () => openExternalUrl(lemonadeGithubUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🍋', style: TextStyle(fontSize: 13, color: muted)),
              const SizedBox(width: 6),
              Text('Backend powered by Lemonade',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 12, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
