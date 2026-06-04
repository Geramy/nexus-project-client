// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/nexus/models/nexus_account_models.dart';
import '../../../infrastructure/nexus/providers/nexus_account_providers.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Cost & Usage tab — per-agent spend pulled live from the Nexus Router
/// (`GET /usage/agents`), attributed via the `X-Nexus-Agent` header each agent
/// sends on its inference calls.
class CostUsageTab extends ConsumerWidget {
  const CostUsageTab({super.key});

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(nexusAuthProvider);
    if (!auth.isSignedIn) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.payments_outlined,
          title: 'Sign in to see agent cost',
          message:
              'Per-agent spend is tracked by the Nexus Router for your '
              'subscription. Sign in on the Account screen to view it.',
        ),
      );
    }

    final report = ref.watch(nexusAgentUsageProvider());

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(nexusAgentUsageProvider),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SectionHeader(
            title: 'Cost & Usage',
            subtitle: 'Per-agent spend this billing period',
          ),
          Gap.lg,
          report.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => NexusCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text('Could not load agent usage: $e'),
            ),
            data: (r) => _buildReport(context, r),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(BuildContext context, AgentUsageReport r) {
    final attributed = r.agents
        .where((a) => a.agent != '(unattributed)')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatTile(
          label: 'Total spend this period',
          value: _money(r.totalCost),
          caption: 'all agents · all tasks',
          icon: Icons.payments_outlined,
        ),
        Gap.lg,
        const SectionHeader(
          title: 'Agents by Cost',
          subtitle: 'attributed via X-Nexus-Agent',
          dense: true,
        ),
        Gap.sm,
        if (r.agents.isEmpty)
          const EmptyState(
            icon: Icons.smart_toy_outlined,
            title: 'No usage yet',
            message:
                'Once your agents run inference through the Router, their '
                'cost will appear here.',
          )
        else
          NexusCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < r.agents.length; i++) ...[
                  if (i > 0) Gap.sm,
                  _CostRow(
                    label: r.agents[i].agent,
                    cost: _money(r.agents[i].cost),
                    detail:
                        '${r.agents[i].calls} calls · '
                        '${r.agents[i].totalTokens} tokens',
                  ),
                ],
              ],
            ),
          ),
        if (attributed.length < r.agents.length) ...[
          Gap.sm,
          Text(
            'Calls without an agent label roll up under “(unattributed)”.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.label,
    required this.cost,
    required this.detail,
  });

  final String label;
  final String cost;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(cost, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
