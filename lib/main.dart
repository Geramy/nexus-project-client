// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/update_provider.dart';
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

/// Resyncs the framework's keyboard state with the engine whenever the app
/// regains focus. Losing focus (a native dialog, Cmd-Tab) can drop a key-up so
/// HardwareKeyboard thinks a key is still held; on return we reconcile so text
/// input keeps working. Debug-only relevance (the desync assertion is stripped
/// from release builds), but harmless everywhere.
class _KeyboardResyncObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      HardwareKeyboard.instance.syncKeyboardState();
    }
  }
}

/// Detects the macOS HardwareKeyboard pressed-state desync assertion
/// (flutter/flutter#125975). A missed key-up (focus loss to a native dialog,
/// hot-restart, key autorepeat) leaves a key "stuck", after which every
/// KeyDownEvent asserts and ALL text input dies in debug builds. When we see it,
/// resync the framework's key state with the engine so typing recovers on the
/// very next keystroke instead of staying broken.
bool _recoverFromKeyboardDesync(Object exception) {
  final msg = exception.toString();
  if (msg.contains('is already pressed') ||
      msg.contains('the physical key is not pressed')) {
    HardwareKeyboard.instance.syncKeyboardState();
    return true;
  }
  return false;
}

/// Reconcile the framework's pressed-key set with the engine whenever focus
/// moves. Cheap and idempotent; fires only on actual focus/highlight changes
/// (not per keystroke), which is exactly when a missed key-up from a native
/// surface would otherwise leave text input dead.
void _syncKeyboardOnFocusChange() {
  HardwareKeyboard.instance.syncKeyboardState();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Print every framework + async error to the console (in addition to any
  // in-UI surfacing). Without this, exceptions thrown off the widget build
  // path (futures, platform channels, isolates) can be swallowed silently.
  FlutterError.onError = (FlutterErrorDetails details) {
    if (_recoverFromKeyboardDesync(details.exception)) return;
    FlutterError.presentError(details);
    debugPrint(
      'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (_recoverFromKeyboardDesync(error)) return true;
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
  // Keep keyboard state reconciled on every focus regain, not just startup, so a
  // missed key-up during a focus change can't permanently break text input.
  WidgetsBinding.instance.addObserver(_KeyboardResyncObserver());

  // Also reconcile on every focus change. A native modal (file/share sheet, the
  // update installer, a mic-permission prompt) can steal a key-up WITHOUT a
  // lifecycle "resumed", leaving a phantom-pressed key that drops text input
  // until focus moves again. This is why "clicking around" recovers it — a focus
  // change. Resyncing on focus changes closes that window automatically, in
  // release builds too (where the desync assertion is stripped and the
  // error-handler recovery never fires), so the user never has to click around.
  FocusManager.instance.addListener(_syncKeyboardOnFocusChange);

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeDatabase(container);
    // Check GitHub for a newer release on launch (desktop release builds only,
    // throttled + gated by the user's "Automatic updates" toggle). Dev/debug
    // builds never auto-update so we don't replace a working local build.
    if (kReleaseMode) {
      container.read(updateControllerProvider).maybeAutoCheck();
    }
    // Resync the framework's key state with the engine. A modifier key pressed
    // during startup/hot-restart can leave a key "stuck" in HardwareKeyboard,
    // which then asserts on the next key-down and kills all text input in debug
    // builds. See https://github.com/flutter/flutter/issues/125975.
    HardwareKeyboard.instance.syncKeyboardState();
  });
}
