// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/infrastructure/inference/scoped_completion.dart';

void main() {
  group('parseJsonObjectArray (scoped-call output)', () {
    test('parses a bare JSON array', () {
      final r = parseJsonObjectArray('[{"title":"A","note":"n"},{"title":"B"}]');
      expect(r.length, 2);
      expect(r[0]['title'], 'A');
      expect(r[1]['title'], 'B');
    });

    test('tolerates ```json code fences', () {
      final r = parseJsonObjectArray('```json\n[{"title":"X"}]\n```');
      expect(r.single['title'], 'X');
    });

    test('tolerates surrounding prose', () {
      final r = parseJsonObjectArray(
        'Sure! Here are the stories:\n[{"title":"Y","description":"d"}]\nHope that helps.',
      );
      expect(r.single['description'], 'd');
    });

    test('returns empty on garbage', () {
      expect(parseJsonObjectArray('not json at all'), isEmpty);
      expect(parseJsonObjectArray(''), isEmpty);
    });
  });
}
