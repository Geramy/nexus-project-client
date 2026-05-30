// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';

import '../../../shared/ui/nexus_ui.dart';

/// Cost & Usage tab (client-scoped) extracted during organization refactor.
class CostUsageTab extends ConsumerWidget {
  const CostUsageTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentClientId = ref.watch(currentClientIdProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Cost & Usage',
            subtitle: 'Client: $currentClientId',
          ),
          Gap.lg,
          StatTile(
            label: 'Total spend this month',
            value: '\$47.82 / \$150',
            caption: 'all agents / all tasks',
            icon: Icons.payments_outlined,
          ),
          Gap.lg,
          SectionHeader(
            title: 'Top Personas by Cost',
            subtitle: 'per current Client',
            dense: true,
          ),
          Gap.sm,
          NexusCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CostRow(label: 'Backend-Specialist', value: '\$18.40'),
                Gap.sm,
                _CostRow(label: 'Mastermind-Core', value: '\$12.10'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
