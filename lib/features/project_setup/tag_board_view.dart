// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/project_tag.dart';
import 'models/tag_category.dart';
import 'providers/tag_providers.dart';
import 'stack_resolver.dart';

/// The Tag Board: the project-profile sections of chips (one per TagCategory). Each
/// chip can be accepted (✓) or rejected (✗); untouched chips stay `proposed`.
/// All state is DB-backed via [tagControllerProvider] so edits persist.
class TagBoardView extends ConsumerWidget {
  const TagBoardView({super.key, required this.projectPk});

  final int projectPk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(projectTagsProvider(projectPk));

    return tagsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load tags: $e')),
      data: (tags) => _board(context, ref, tags),
    );
  }

  Widget _board(BuildContext context, WidgetRef ref, List<ProjectTag> tags) {
    final byCategory = <TagCategory, List<ProjectTag>>{
      for (final c in TagCategory.values) c: [],
    };
    for (final t in tags) {
      byCategory[t.category]!.add(t);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ResolveBar(projectPk: projectPk),
        const SizedBox(height: 8),
        for (final category in TagCategory.values)
          _TagSection(
            projectPk: projectPk,
            category: category,
            tags: byCategory[category]!,
          ),
      ],
    );
  }
}

/// Runs the deterministic resolver over the current intent tags and upserts the
/// proposed stack tags. Lets the user materialize the Client↔Server↔DB stack.
class _ResolveBar extends ConsumerStatefulWidget {
  const _ResolveBar({required this.projectPk});
  final int projectPk;

  @override
  ConsumerState<_ResolveBar> createState() => _ResolveBarState();
}

class _ResolveBarState extends ConsumerState<_ResolveBar> {
  bool _busy = false;

  Future<void> _resolve() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final tags =
          ref.read(projectTagsProvider(widget.projectPk)).valueOrNull ?? [];
      final resolved = const StackResolver().resolve(tags);
      final controller = ref.read(tagControllerProvider(widget.projectPk));
      for (final tag in resolved.stackTags) {
        await controller.upsert(tag);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.account_tree_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Resolve the stack from your platforms & objectives '
                '(Client ↔ Server ↔ PostgreSQL).',
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _resolve,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('Resolve stack'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagSection extends ConsumerWidget {
  const _TagSection({
    required this.projectPk,
    required this.category,
    required this.tags,
  });

  final int projectPk;
  final TagCategory category;
  final List<ProjectTag> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(category.label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${tags.where((t) => !t.isRejected).length}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showAddPicker(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (tags.isEmpty)
            Text('No tags yet.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  _TagChip(projectPk: projectPk, tag: tag),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showAddPicker(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(tagControllerProvider(projectPk));
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _AddTagDialog(category: category),
    );
    if (value == null || value.trim().isEmpty) return;
    await controller.addManual(category: category, value: value.trim());
  }
}

class _TagChip extends ConsumerWidget {
  const _TagChip({required this.projectPk, required this.tag});

  final int projectPk;
  final ProjectTag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(tagControllerProvider(projectPk));
    final pk = tag.tagPk;

    final bg = switch (tag.status) {
      TagStatus.accepted => theme.colorScheme.primaryContainer,
      TagStatus.rejected => theme.colorScheme.surfaceContainerHighest,
      TagStatus.proposed => Colors.transparent,
    };
    final border = tag.isProposed
        ? Border.all(color: theme.colorScheme.outlineVariant, style: BorderStyle.solid)
        : null;

    return Tooltip(
      message: tag.rationale ?? '',
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tag.verdict != null) ...[
              _VerdictDot(verdict: tag.verdict!),
              const SizedBox(width: 6),
            ],
            Text(
              tag.value,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration:
                    tag.isRejected ? TextDecoration.lineThrough : null,
                color: tag.isRejected ? theme.colorScheme.outline : null,
              ),
            ),
            if (tag.forLanguage != null) ...[
              const SizedBox(width: 6),
              _MetaPill(text: tag.forLanguage!, theme: theme),
            ] else if (tag.layerKey != null) ...[
              const SizedBox(width: 6),
              Text(
                tag.layerKey!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(width: 4),
            if (pk != null) ..._actions(context, controller, pk, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, TagController controller,
      int pk, ThemeData theme) {
    return [
      _IconBtn(
        icon: Icons.check,
        active: tag.isAccepted,
        color: Colors.green,
        tooltip: 'Accept',
        onTap: () =>
            tag.isAccepted ? controller.reset(pk) : controller.accept(pk),
      ),
      _IconBtn(
        icon: Icons.close,
        active: tag.isRejected,
        color: theme.colorScheme.error,
        tooltip: 'Reject',
        onTap: () =>
            tag.isRejected ? controller.reset(pk) : controller.reject(pk),
      ),
      if (tag.source == TagSource.user)
        _IconBtn(
          icon: Icons.delete_outline,
          active: false,
          color: theme.colorScheme.outline,
          tooltip: 'Remove',
          onTap: () => controller.remove(pk),
        ),
    ];
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.active,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon,
              size: 16,
              color: active ? color : Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

/// Small rounded label used for a library's attached language (e.g. "Dart").
class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.text, required this.theme});
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Freshness verdict dot: fresh=green, aging=amber, stale=orange, dead=red.
class _VerdictDot extends StatelessWidget {
  const _VerdictDot({required this.verdict});
  final String verdict;

  @override
  Widget build(BuildContext context) {
    final color = switch (verdict) {
      'fresh' => Colors.green,
      'aging' => Colors.amber,
      'stale' => Colors.orange,
      'dead' => Colors.red,
      _ => Colors.grey,
    };
    return Tooltip(
      message: verdict,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Add-tag dialog. Closed/curated categories show their vocabulary as choices;
/// curated + open also allow a free-text entry.
class _AddTagDialog extends StatefulWidget {
  const _AddTagDialog({required this.category});
  final TagCategory category;

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vocab = widget.category.vocabulary;
    final kind = widget.category.vocab;
    final allowsFreeText = kind != VocabKind.closed;

    return AlertDialog(
      title: Text('Add to ${widget.category.label}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (vocab.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in vocab)
                    ActionChip(
                      label: Text(v),
                      onPressed: () => Navigator.of(context).pop(v),
                    ),
                ],
              ),
            if (allowsFreeText) ...[
              if (vocab.isNotEmpty) const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: vocab.isEmpty,
                decoration: InputDecoration(
                  labelText: kind == VocabKind.open
                      ? 'Package / repo name'
                      : 'Custom value',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (allowsFreeText)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text),
            child: const Text('Add'),
          ),
      ],
    );
  }
}
