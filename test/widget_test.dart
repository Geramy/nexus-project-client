// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexus_projects_client/shared/ui/app_theme.dart';

void main() {
  test('every theme choice maps to a usable ThemeData', () {
    for (final choice in AppThemeChoice.values) {
      expect(AppTheme.of(choice), isA<ThemeData>());
    }
  });

  test('fromName round-trips and falls back to the default', () {
    expect(AppThemeChoice.fromName('midnight'), AppThemeChoice.midnight);
    expect(AppThemeChoice.fromName('does-not-exist'), AppThemeChoice.defaultChoice);
  });

  testWidgets('a MaterialApp renders under the default theme', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.of(AppThemeChoice.defaultChoice),
          home: const Scaffold(body: Center(child: Text('Nexus Projects'))),
        ),
      ),
    );

    expect(find.text('Nexus Projects'), findsOneWidget);
  });
}
