// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

/// Small badge shown next to the page title.
class InfrastructureBadge extends StatelessWidget {
  const InfrastructureBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'Local Lemonade Infrastructure',
        style: TextStyle(fontSize: 11, color: Colors.deepPurple, fontWeight: FontWeight.w600),
      ),
    );
  }
}
