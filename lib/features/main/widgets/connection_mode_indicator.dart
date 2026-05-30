// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

class ConnectionModeIndicator extends StatelessWidget {
  final String mode; // 'local' or 'remote'

  const ConnectionModeIndicator({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final isLocal = mode == 'local';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isLocal ? Colors.green.withValues(alpha: 0.12) : Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLocal ? Colors.green.withValues(alpha: 0.4) : Colors.blue.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocal ? Icons.computer : Icons.cloud_queue,
            size: 15,
            color: isLocal ? Colors.green.shade700 : Colors.blue.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            isLocal ? 'Local (Free)' : 'Remote (Routed)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isLocal ? Colors.green.shade700 : Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
