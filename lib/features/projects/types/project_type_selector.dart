// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import '../../../shared/ui/nexus_ui.dart';
import 'project_type.dart';

/// Picks the project TYPE (and a sub-category when the type has them). The type
/// determines which capabilities/UI the project gets and which agent pack(s) are
/// provisioned. Stateless: the parent owns [selectedTypeKey]/[selectedSubKey].
class ProjectTypeSelector extends StatelessWidget {
  const ProjectTypeSelector({
    super.key,
    required this.selectedTypeKey,
    required this.selectedSubKey,
    required this.onTypeChanged,
    required this.onSubChanged,
  });

  final String selectedTypeKey;
  final String? selectedSubKey;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String?> onSubChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = projectTypeByKey(selectedTypeKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in kProjectTypes) ...[
          _TypeCard(
            type: type,
            selected: type.key == selectedTypeKey,
            onTap: () {
              onTypeChanged(type.key);
              // Reset sub-category to the new type's first option (or none).
              onSubChanged(
                  type.subCategories.isEmpty ? null : type.subCategories.first.key);
            },
          ),
          Gap.sm,
        ],
        if (selected.subCategories.isNotEmpty) ...[
          Gap.xs,
          Text('What kind?', style: theme.textTheme.titleSmall),
          Gap.xs,
          InputDecorator(
            decoration: const InputDecoration(border: OutlineInputBorder()),
            child: DropdownButton<String>(
              value: selectedSubKey ?? selected.subCategories.first.key,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in selected.subCategories)
                  DropdownMenuItem(value: s.key, child: Text(s.name)),
              ],
              onChanged: (v) => onSubChanged(v),
            ),
          ),
          if (selectedSubKey != null) ...[
            Gap.xs,
            Text(
              selected.subCategories
                  .firstWhere((s) => s.key == selectedSubKey,
                      orElse: () => selected.subCategories.first)
                  .description,
              style: theme.textTheme.bodySmall?.copyWith(color: context.nx.textMuted),
            ),
          ],
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard(
      {required this.type, required this.selected, required this.onTap});

  final ProjectType type;
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
          Icon(type.icon, size: 22, color: context.nx.textMuted),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(type.tagline, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
