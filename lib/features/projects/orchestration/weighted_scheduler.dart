// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Smooth weighted round-robin (the nginx SWRR algorithm).
///
/// [pick] takes the current per-key weights (e.g. each pipeline stage's backlog
/// size) and returns the key to serve next. Over many picks the selection
/// converges to the weight ratio ("who has more to do" goes more often), yet
/// every key with a positive weight is guaranteed a turn — no starvation. The
/// distribution is also *smooth*: a heavier key doesn't monopolize a long run
/// before the lighter ones get a turn.
///
/// Stateful across calls (it carries the per-key credit), so reuse one instance.
class WeightedRoundRobin<K> {
  final Map<K, double> _credit = {};

  /// Returns the next key to serve given [weights], or null when nothing has a
  /// positive weight. Keys absent or non-positive in [weights] are dropped.
  K? pick(Map<K, int> weights) {
    final active = <K, int>{
      for (final e in weights.entries)
        if (e.value > 0) e.key: e.value,
    };
    // Forget credit for keys that no longer have work, so they don't bank it.
    _credit.removeWhere((k, _) => !active.containsKey(k));
    if (active.isEmpty) return null;

    final total = active.values.fold<int>(0, (a, b) => a + b);
    K? best;
    var bestVal = double.negativeInfinity;
    active.forEach((k, w) {
      final v = (_credit[k] ?? 0) + w;
      _credit[k] = v;
      if (v > bestVal) {
        bestVal = v;
        best = k;
      }
    });
    if (best != null) _credit[best as K] = (_credit[best] ?? 0) - total;
    return best;
  }

  /// Drop all accumulated credit (e.g. on a hard reset).
  void reset() => _credit.clear();
}
