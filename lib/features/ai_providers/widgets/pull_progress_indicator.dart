// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import 'package:nexus_projects_client/infrastructure/lemonade/api/endpoints/admin_endpoint.dart';

/// Progress indicator for model pull operations.
class PullProgressIndicator extends StatelessWidget {
  final PullProgress progress;

  const PullProgressIndicator({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: (progress.percent ?? 0) / 100),
          const SizedBox(height: 4),
          Text(
            'Downloading ${progress.file ?? ''} (${progress.percent?.toStringAsFixed(1) ?? '?'}%)',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
