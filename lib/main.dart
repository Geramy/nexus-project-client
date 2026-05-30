// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers/database_provider.dart';
import 'infrastructure/database/database_seeder.dart';

Future<void> _initializeDatabase(ProviderContainer container) async {
  try {
    final db = container.read(nexusDatabaseProvider);
    await seedInitialData(db);
  } catch (e, st) {
    // Log but do not crash the app. The UI providers already handle loading/error states.
    debugPrint('Database initialization/seed warning: $e\n$st');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Print every framework + async error to the console (in addition to any
  // in-UI surfacing). Without this, exceptions thrown off the widget build
  // path (futures, platform channels, isolates) can be swallowed silently.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error\n$stack');
    return true;
  };

  final container = ProviderContainer();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NexusProjectsApp(),
    ),
  );

  // Seed AFTER the first frame. Running it before runApp() (as we used to) tried
  // to use the path_provider platform channel before the engine was ready,
  // failing with "Channel was closed before receiving a response" on macOS — so
  // the Default client never got seeded. By the first post-frame callback the
  // channels are up. The seed is idempotent and widgets use AsyncValue.when(...).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeDatabase(container);
    // Resync the framework's key state with the engine. A modifier key pressed
    // during startup/hot-restart can leave a key "stuck" in HardwareKeyboard,
    // which then asserts on the next key-down and kills all text input in debug
    // builds. See https://github.com/flutter/flutter/issues/125975.
    HardwareKeyboard.instance.syncKeyboardState();
  });
}
