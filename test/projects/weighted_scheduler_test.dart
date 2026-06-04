// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/features/projects/orchestration/weighted_scheduler.dart';

void main() {
  group('WeightedRoundRobin', () {
    test('distributes proportionally and starves no one', () {
      final wrr = WeightedRoundRobin<String>();
      const weights = {'implement': 8, 'verify': 3, 'merge': 1};
      final counts = <String, int>{'implement': 0, 'verify': 0, 'merge': 0};
      const total = 12;
      const rounds = 100;
      for (var i = 0; i < total * rounds; i++) {
        final k = wrr.pick(weights)!;
        counts[k] = counts[k]! + 1;
      }
      // Exact proportional distribution for SWRR with stable weights.
      expect(counts['implement'], 8 * rounds);
      expect(counts['verify'], 3 * rounds);
      expect(counts['merge'], 1 * rounds);
      // None starved.
      expect(counts.values.every((c) => c > 0), isTrue);
    });

    test('the light key gets a turn within a bounded interval (smoothness)', () {
      final wrr = WeightedRoundRobin<String>();
      const weights = {'heavy': 9, 'light': 1};
      var sinceLight = 0;
      var maxGap = 0;
      for (var i = 0; i < 200; i++) {
        final k = wrr.pick(weights)!;
        if (k == 'light') {
          maxGap = sinceLight > maxGap ? sinceLight : maxGap;
          sinceLight = 0;
        } else {
          sinceLight++;
        }
      }
      // With total weight 10, the light key surfaces ~every 10 picks — never a
      // long monopoly by the heavy key.
      expect(maxGap, lessThanOrEqualTo(10));
    });

    test('adapts when a stage empties out, and never picks an empty one', () {
      final wrr = WeightedRoundRobin<String>();
      // implement drained; only verify + merge remain.
      final picks = <String>[];
      for (var i = 0; i < 8; i++) {
        picks.add(wrr.pick({'verify': 3, 'merge': 1})!);
      }
      expect(picks.contains('implement'), isFalse);
      expect(picks.contains('verify'), isTrue);
      expect(picks.contains('merge'), isTrue);
    });

    test('returns null when there is no work', () {
      final wrr = WeightedRoundRobin<String>();
      expect(wrr.pick(const {}), isNull);
      expect(wrr.pick(const {'a': 0}), isNull);
    });
  });
}
