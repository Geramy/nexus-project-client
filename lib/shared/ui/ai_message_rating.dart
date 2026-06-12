// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The result of rating an AI message: the star count, any low-rating reasons
/// the user ticked, and an optional free-text "other" reason (≤50 chars).
class AiRatingResult {
  const AiRatingResult({
    required this.stars,
    this.reasons = const [],
    this.other,
  });
  final int stars;
  final List<String> reasons;
  final String? other;
}

/// The fixed low-rating reasons (shown when a rating is 1–2 stars).
const List<String> kAiRatingReasons = [
  'Repeated question',
  'Not related to the topic',
  'Unreadable text',
  'Server unavailable',
];

/// A compact 1–5 star rating row that sits beneath an AI message. Tapping a star
/// rates it; a low rating (1–2) opens a small reasons popup (all optional — the
/// user can just hit Submit). Already-rated messages show their stars filled.
class AiMessageRating extends StatelessWidget {
  const AiMessageRating({
    super.key,
    required this.stars,
    required this.onSubmit,
    this.label = 'Rate this reply',
  });

  /// The current rating (1–5), or null if not yet rated.
  final int? stars;

  /// Called with the final rating once the user picks stars (and, for a low
  /// rating, dismisses the reasons popup with Submit).
  final void Function(AiRatingResult result) onSubmit;

  final String label;

  Future<void> _handleTap(BuildContext context, int picked) async {
    if (picked >= 3) {
      onSubmit(AiRatingResult(stars: picked));
      return;
    }
    // Low rating → ask why (optional).
    final result = await showDialog<AiRatingResult>(
      context: context,
      builder: (_) => _RatingReasonsDialog(stars: picked),
    );
    if (result != null) onSubmit(result);
  }

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final current = stars ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stars == null ? label : 'Rated',
            style: TextStyle(fontSize: 10.5, color: nx.textFaint),
          ),
          const SizedBox(width: 4),
          for (var i = 1; i <= 5; i++)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _handleTap(context, i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                child: Icon(
                  i <= current ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 18,
                  color: i <= current
                      ? const Color(0xFFF5B301) // amber reads on every theme
                      : nx.textFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The optional "why was this low?" popup for a 1–2 star rating. Ticking reasons
/// and the free-text "other" are all optional — Submit works empty (it's just a
/// more-info prompt).
class _RatingReasonsDialog extends StatefulWidget {
  const _RatingReasonsDialog({required this.stars});
  final int stars;

  @override
  State<_RatingReasonsDialog> createState() => _RatingReasonsDialogState();
}

class _RatingReasonsDialogState extends State<_RatingReasonsDialog> {
  final Set<String> _picked = {};
  final _other = TextEditingController();
  bool _otherOn = false;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rated ${widget.stars} ★ — anything we should know?'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optional — tap any that apply (or just Submit).',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (final reason in kAiRatingReasons)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _picked.contains(reason),
                title: Text(reason, style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _picked.add(reason);
                  } else {
                    _picked.remove(reason);
                  }
                }),
              ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _otherOn,
              title: const Text('Other', style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _otherOn = v == true),
            ),
            if (_otherOn)
              TextField(
                controller: _other,
                maxLength: 50,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'In 50 characters or less…',
                  border: OutlineInputBorder(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final other = _otherOn ? _other.text.trim() : '';
            Navigator.pop(
              context,
              AiRatingResult(
                stars: widget.stars,
                reasons: _picked.toList(),
                other: other.isEmpty ? null : other,
              ),
            );
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
