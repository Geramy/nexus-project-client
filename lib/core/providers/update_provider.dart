// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/update/github_release_client.dart';
import '../../infrastructure/update/update_downloader.dart';
import '../../infrastructure/update/update_installer.dart';
import '../../infrastructure/update/update_models.dart';

/// Where the updater is in its lifecycle. Drives the settings card + the
/// floating banner.
enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  launching,
  error,
}

/// Holds the live updater state and orchestrates check → download → verify →
/// launch. Manual `ChangeNotifierProvider` (like [setupChatControllerProvider])
/// so the Account card and the global banner share one instance.
class UpdateController extends ChangeNotifier {
  UpdateController(
    this._ref, {
    GithubReleaseClient? client,
    UpdateDownloader? downloader,
    UpdateInstaller installer = const UpdateInstaller(),
  }) : _client = client ?? GithubReleaseClient(),
       _downloader = downloader ?? UpdateDownloader(),
       _installer = installer;

  // ignore: unused_field
  final Ref _ref;
  final GithubReleaseClient _client;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;

  static const _kAutoCheck = 'auto_update_enabled';
  static const _kLastCheck = 'auto_update_last_check';
  static const _kSkipped = 'auto_update_skipped_version';

  UpdatePhase phase = UpdatePhase.idle;
  SemVer? currentVersion;
  AppRelease? latest;
  String? errorMessage;

  // Download progress.
  int receivedBytes = 0;
  int? totalBytes;

  bool autoCheck = true;
  int _lastCheckMs = 0;
  String? _skippedVersion;
  bool _loaded = false;
  bool _busy = false;

  /// True when an update for the running platform is ready to offer.
  bool get hasUpdate =>
      latest != null && latest!.assetForThisPlatform() != null;

  /// Fraction 0..1 of the active download, or null when total is unknown.
  double? get progress => (totalBytes != null && totalBytes! > 0)
      ? receivedBytes / totalBytes!
      : null;

  /// Updates are only supported on desktop platforms.
  bool get supported => PlatformTarget.current != null;

  /// Load the running version + persisted prefs. Idempotent.
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = SemVer.tryParse(info.version);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    autoCheck = prefs.getBool(_kAutoCheck) ?? true;
    _lastCheckMs = prefs.getInt(_kLastCheck) ?? 0;
    _skippedVersion = prefs.getString(_kSkipped);
    notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    autoCheck = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoCheck, value);
  }

  /// How long since the last automatic check.
  Duration get sinceLastCheck => Duration(
    milliseconds: DateTime.now().millisecondsSinceEpoch - _lastCheckMs,
  );

  /// App-launch entry point: checks for updates only if supported, enabled, and
  /// not checked within [throttle]. Safe to call unconditionally — the caller
  /// gates on release mode so dev builds never self-update.
  Future<void> maybeAutoCheck({
    Duration throttle = const Duration(hours: 6),
  }) async {
    if (!supported) return;
    await init();
    if (!autoCheck) return;
    if (_lastCheckMs != 0 && sinceLastCheck < throttle) return;
    await checkForUpdates();
  }

  /// Fetch the latest release and compare. [manual] checks surface errors and
  /// ignore a previously "skipped" version; auto checks stay quiet.
  Future<void> checkForUpdates({bool manual = false}) async {
    if (_busy || !supported) return;
    await init();
    _busy = true;
    errorMessage = null;
    phase = UpdatePhase.checking;
    notifyListeners();

    try {
      final release = await _client.fetchLatest();
      await _recordCheckTime();

      final cur = currentVersion;
      final isNewer = cur == null || release.version.isNewerThan(cur);
      final skipped =
          !manual &&
          _skippedVersion != null &&
          release.version.toString() == _skippedVersion;

      if (isNewer && !skipped && release.assetForThisPlatform() != null) {
        latest = release;
        phase = UpdatePhase.available;
      } else {
        latest = null;
        phase = UpdatePhase.upToDate;
      }
    } catch (e) {
      if (manual) {
        errorMessage = e is ReleaseLookupException ? e.message : '$e';
        phase = UpdatePhase.error;
      } else {
        phase = UpdatePhase.idle; // stay silent on background failures
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Download the platform installer, verify it against the published
  /// SHA256SUMS, launch it, and quit. No-op if no update is staged.
  Future<void> startUpdate() async {
    final release = latest;
    if (_busy || release == null) return;
    final asset = release.assetForThisPlatform();
    final sums = release.checksumsAsset();
    if (asset == null) return;
    if (sums == null) {
      _fail('This release has no checksum manifest, so it can\'t be verified.');
      return;
    }

    _busy = true;
    errorMessage = null;
    receivedBytes = 0;
    totalBytes = asset.sizeBytes > 0 ? asset.sizeBytes : null;
    phase = UpdatePhase.downloading;
    notifyListeners();

    try {
      await _downloader.cleanStaging();
      final file = await _downloader.download(
        asset.url,
        asset.name,
        onProgress: (received, total) {
          receivedBytes = received;
          if (total != null) totalBytes = total;
          notifyListeners();
        },
      );

      phase = UpdatePhase.verifying;
      notifyListeners();
      final checksums = await _downloader.fetchChecksums(sums.url);
      final expected = checksums[asset.name];
      if (expected == null) {
        await _safeDelete(file);
        _fail('No checksum found for ${asset.name}.');
        return;
      }
      final ok = await UpdateDownloader.verify(file, expected);
      if (!ok) {
        await _safeDelete(file);
        _fail('Checksum did not match — the download may be corrupt.');
        return;
      }

      phase = UpdatePhase.launching;
      notifyListeners();
      final launched = await _installer.launchInstaller(file);
      if (!launched) {
        _fail('Could not launch the installer. Opening its location instead.');
        await _installer.revealInFolder(file);
        return;
      }
      // Hand off to the OS installer and exit so it can replace the app.
      await _installer.quitForInstall();
    } catch (e) {
      _fail('Update failed: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Open the release's "What's new" page in the browser.
  Future<void> openReleaseNotes() async {
    final url = latest?.notesUrl;
    if (url != null) await _installer.openExternal(url);
  }

  /// Hide the banner for this version permanently (until a newer one ships).
  Future<void> skipThisVersion() async {
    final v = latest?.version.toString();
    if (v != null) {
      _skippedVersion = v;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSkipped, v);
    }
    latest = null;
    phase = UpdatePhase.idle;
    notifyListeners();
  }

  /// Dismiss the banner without skipping (it returns next launch).
  void dismiss() {
    if (phase == UpdatePhase.available) {
      phase = UpdatePhase.idle;
      notifyListeners();
    }
  }

  void _fail(String message) {
    errorMessage = message;
    phase = UpdatePhase.error;
    notifyListeners();
  }

  Future<void> _recordCheckTime() async {
    _lastCheckMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastCheck, _lastCheckMs);
  }

  Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _client.dispose();
    _downloader.dispose();
    super.dispose();
  }
}

/// App-wide updater state, shared by the Account settings card and the global
/// update banner.
final updateControllerProvider = ChangeNotifierProvider<UpdateController>((
  ref,
) {
  final c = UpdateController(ref);
  // Kick off the version/prefs load; the check itself is triggered explicitly.
  c.init();
  return c;
});
