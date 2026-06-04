// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Plans + add-ons catalog. Each plan is a Card with its entitlements and a
/// Subscribe / Change plan button that starts a Stripe Checkout (with any
/// selected add-ons) and opens the returned URL in the browser.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../infrastructure/lemonade/api/exceptions.dart';
import '../../../infrastructure/nexus/models/nexus_account_models.dart';
import '../../../infrastructure/nexus/nexus_url_launcher.dart';
import '../../../infrastructure/nexus/providers/nexus_account_providers.dart';

class PlanCatalogSection extends ConsumerStatefulWidget {
  const PlanCatalogSection({super.key});

  @override
  ConsumerState<PlanCatalogSection> createState() => _PlanCatalogSectionState();
}

class _PlanCatalogSectionState extends ConsumerState<PlanCatalogSection> {
  final Set<String> _selectedAddons = {};
  String? _checkingOutPlan; // plan key currently being checked out

  Future<void> _subscribe(Plan plan) async {
    setState(() => _checkingOutPlan = plan.key);
    try {
      final client = ref.read(nexusAuthProvider.notifier).authedClient();
      final url = await client.startCheckout(
        plan: plan.key,
        addons: _selectedAddons.toList(),
      );
      final ok = await openExternalUrl(url);
      if (!ok && mounted) {
        _snack('Could not open checkout. URL: $url');
      }
    } on LemonadeApiException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _checkingOutPlan = null);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(nexusPlansProvider);
    final currentPlanKey = ref
        .watch(nexusAccountSummaryProvider)
        .maybeWhen(data: (a) => a.subscription.planKey, orElse: () => null);

    return catalogAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => _error(context, e),
      data: (catalog) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plans', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: catalog.plans
                  .map(
                    (p) => SizedBox(
                      width: 260,
                      child: _PlanCard(
                        plan: p,
                        isCurrent: p.key == currentPlanKey,
                        busy: _checkingOutPlan == p.key,
                        anyBusy: _checkingOutPlan != null,
                        onSubscribe: () => _subscribe(p),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (catalog.addons.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('Add-ons', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Select add-ons to include in your next checkout.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Column(
                children: catalog.addons.map((a) {
                  final selected = _selectedAddons.contains(a.key);
                  return Card(
                    child: CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedAddons.add(a.key);
                          } else {
                            _selectedAddons.remove(a.key);
                          }
                        });
                      },
                      title: Text(a.name),
                      subtitle: Text(_addonSubtitle(a)),
                      secondary: Text(
                        _price(a.priceCents),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _error(BuildContext context, Object e) {
    final msg = e is LemonadeApiException ? e.message : e.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Could not load plans: $msg')),
            TextButton(
              onPressed: () => ref.invalidate(nexusPlansProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.busy,
    required this.anyBusy,
    required this.onSubscribe,
  });

  final Plan plan;
  final bool isCurrent;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? BorderSide(color: scheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Current',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _price(plan.priceCents),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('/ month', style: Theme.of(context).textTheme.bodySmall),
            if (plan.description != null && plan.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                plan.description!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            _feature(
              context,
              Icons.token_outlined,
              '${_fmt(plan.monthlyTokens)} tokens / mo',
            ),
            _feature(
              context,
              Icons.image_outlined,
              '${_fmt(plan.monthlyImages)} images / mo',
            ),
            _feature(
              context,
              Icons.groups_outlined,
              '${plan.agentSessions} agent sessions',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: anyBusy ? null : onSubscribe,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isCurrent ? 'Change plan' : 'Subscribe'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

String _addonSubtitle(AddOn a) {
  final parts = <String>[];
  if (a.bonusTokens > 0) parts.add('+${_fmt(a.bonusTokens)} tokens');
  if (a.bonusImages > 0) parts.add('+${_fmt(a.bonusImages)} images');
  if (a.bonusAgentSessions > 0) {
    parts.add('+${a.bonusAgentSessions} agent sessions');
  }
  final bonuses = parts.isEmpty ? '' : parts.join(' · ');
  if (a.description != null && a.description!.isNotEmpty) {
    return bonuses.isEmpty ? a.description! : '${a.description!}\n$bonuses';
  }
  return bonuses;
}

String _price(int cents) => NumberFormat.simpleCurrency().format(cents / 100.0);

String _fmt(int v) => NumberFormat.compact().format(v);
