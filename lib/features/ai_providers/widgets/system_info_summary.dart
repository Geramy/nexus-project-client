// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import 'info_row_chip.dart';

/// Displays system info as a row of small labeled chips.
class SystemInfoSummary extends StatelessWidget {
  final Map<String, dynamic> info;

  const SystemInfoSummary({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final entries = <InfoRowChip>[
      if (info['hostname'] != null)
        InfoRowChip(label: 'Hostname', value: info['hostname'].toString()),
      if (info['os'] != null)
        InfoRowChip(label: 'OS', value: info['os'].toString()),
      if (info['cpu'] != null)
        InfoRowChip(label: 'CPU', value: info['cpu'].toString()),
      if (info['memory_total'] != null)
        InfoRowChip(
          label: 'Memory',
          value: '${(info['memory_total'] as num?)?.toDouble() ?? 0} GB',
        ),
      if (info['cuda_available'] != null)
        InfoRowChip(
          label: 'CUDA',
          value: info['cuda_available'] == true ? 'Available' : 'Not Available',
        ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 12, runSpacing: 8, children: entries);
  }
}
