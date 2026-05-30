// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

/// Single info key-value chip.
class InfoRowChip extends StatelessWidget {
  final String label;
  final String value;

  const InfoRowChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label:', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
