// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Opens an external URL (Stripe Checkout / billing portal) in the user's
/// default browser.
///
/// NOTE: `url_launcher` is NOT in pubspec.yaml, and the app has no existing
/// external-link mechanism. Since this is a desktop-first Flutter app
/// (macOS/Windows/Linux), we shell out to the platform "open" command. If
/// `url_launcher` is added later, swap [openExternalUrl] to use launchUrl.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Returns true on success. Throws nothing — callers surface a message instead.
Future<bool> openExternalUrl(String url) async {
  if (url.isEmpty) return false;
  try {
    final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      // `start` is a cmd builtin; route through cmd. Empty first arg is the
      // window title placeholder.
      result = await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', [url]);
    } else {
      // iOS/Android/web: no shell. url_launcher would be required here.
      debugPrint('[Nexus] openExternalUrl unsupported on this platform; url=$url');
      return false;
    }
    return result.exitCode == 0;
  } catch (e) {
    debugPrint('[Nexus] openExternalUrl failed: $e');
    return false;
  }
}
