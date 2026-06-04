// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Usage meter card: progress bars for token + image consumption with
/// used/limit text, plus a "Throttled" badge when over the token cap.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../infrastructure/nexus/models/nexus_account_models.dart';

class UsageMeterCard extends StatelessWidget {
  const UsageMeterCard({super.key, required this.usage});
  final UsageSnapshot usage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Usage this period',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 10),
                if (usage.throttled) _ThrottledBadge(tps: usage.throttleTps),
              ],
            ),
            const SizedBox(height: 16),
            _MeterRow(label: 'Tokens', meter: usage.tokens),
            const SizedBox(height: 16),
            _MeterRow(label: 'Images', meter: usage.images),
            const SizedBox(height: 16),
            Text(
              'Max concurrent connections: ${usage.maxConcurrentConnections}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.label, required this.meter});
  final String label;
  final UsageMeter meter;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.decimalPattern();
    final over = meter.percent >= 100;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              '${fmt.format(meter.used)} / ${fmt.format(meter.limit)}'
              '  (${meter.percent.toStringAsFixed(0)}%)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: meter.fraction,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              over ? scheme.error : scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThrottledBadge extends StatelessWidget {
  const _ThrottledBadge({this.tps});
  final int? tps;

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    final label = tps != null ? 'Throttled · $tps tps' : 'Throttled';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
