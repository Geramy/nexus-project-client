// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../agents/packs/agent_pack_catalog.dart';
import '../../../shared/ui/nexus_ui.dart';

/// A multi-select picker for the agent packs to provision into a client.
///
/// Stateless: the parent owns [selected] and is notified via [onChanged]. At
/// least one pack must stay selected — deselecting the last one is a no-op so a
/// client always gets a team. Reused by the onboarding wizard's project step and
/// the new-client / new-project dialogs.
class PackSelector extends StatelessWidget {
  const PackSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  void _toggle(String key) {
    final next = Set<String>.from(selected);
    if (next.contains(key)) {
      if (next.length == 1) return; // keep at least one pack
      next.remove(key);
    } else {
      next.add(key);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pack in kAgentPacks) ...[
          _PackCard(
            pack: pack,
            selected: selected.contains(pack.key),
            onTap: () => _toggle(pack.key),
          ),
          Gap.sm,
        ],
      ],
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.selected,
    required this.onTap,
  });

  final AgentPack pack;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexusCard(
      onTap: onTap,
      selected: selected,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? theme.colorScheme.primary : context.nx.textMuted,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Icon(pack.icon, size: 22, color: context.nx.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(pack.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (pack.fullyWired) const _WiredBadge(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(pack.tagline, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  '${pack.agents.length} agent${pack.agents.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: context.nx.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WiredBadge extends StatelessWidget {
  const _WiredBadge();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Text('Ready',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
