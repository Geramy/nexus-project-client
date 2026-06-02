// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Secure persistence for the Nexus ACCOUNT credential. Parallels
/// infrastructure/lemonade/services/secure_key_store.dart (a thin wrapper over
/// flutter_secure_storage) but is dedicated to the single account token + a
/// cached copy of the user/client JSON so the UI can hydrate on launch without
/// a round-trip.
///
/// The token NEVER touches SharedPreferences or Drift — only the keychain.
/// The token is never logged.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/nexus_account_models.dart';

class NexusAccountStore {
  /// Team-id-prefixed keychain access group. MUST match the
  /// `keychain-access-groups` entitlement in macos/Runner/Release.entitlements
  /// AND the Developer ID signing team (YBQ9BU6Q6F).
  static const _macAccessGroup =
      'YBQ9BU6Q6F.com.nexusprojects.nexusProjectsClient';

  /// SILENT path — the modern data-protection keychain, scoped to our access
  /// group. macOS reads/writes it without the "…wants to use your keychain"
  /// prompt, but it only works in a properly Developer-ID-signed + entitled
  /// build (the shipped release). Ad-hoc/debug builds can't carry the
  /// entitlement, so this is used in RELEASE only.
  static final FlutterSecureStorage _dataProtection = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
    iOptions:
        const IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: const MacOsOptions(
      useDataProtectionKeyChain: true,
      accessibility: KeychainAccessibility.first_unlock,
      groupId: _macAccessGroup,
    ),
  );

  /// FALLBACK path — the legacy file-based keychain. Needs no entitlement and
  /// works in ad-hoc-signed debug/local builds (where the data-protection
  /// keychain would SIGKILL at launch or throw errSecMissingEntitlement). It
  /// prompts for access on macOS, which is why release prefers the silent path.
  static final FlutterSecureStorage _fileBased = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
    iOptions:
        const IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: const MacOsOptions(useDataProtectionKeyChain: false),
  );

  /// Preferred store: the silent keychain in release builds, file-based in debug.
  static FlutterSecureStorage _store =
      kReleaseMode ? _dataProtection : _fileBased;
  static bool _fellBack = false;

  /// Runs a keychain op against the preferred store. If the data-protection
  /// keychain isn't usable on this build (e.g. an unentitled build throws
  /// errSecMissingEntitlement), fall back to the file-based keychain for the
  /// rest of the session so authentication never hard-breaks.
  static Future<T> _op<T>(
      Future<T> Function(FlutterSecureStorage s) run) async {
    try {
      return await run(_store);
    } on PlatformException {
      if (!_fellBack && identical(_store, _dataProtection)) {
        _fellBack = true;
        _store = _fileBased;
        return await run(_fileBased);
      }
      rethrow;
    }
  }

  static const _tokenKey = 'nexus/account_token';
  static const _identityKey = 'nexus/account_identity';
  static const _gatewayKey = 'nexus/gateway_base_url';

  // ── Token ───────────────────────────────────────────────────────────

  static Future<String?> readToken() => _op((s) => s.read(key: _tokenKey));

  static Future<void> writeToken(String token) =>
      _op((s) => s.write(key: _tokenKey, value: token));

  static Future<void> deleteToken() => _op((s) => s.delete(key: _tokenKey));

  // ── Cached identity (user + client) ─────────────────────────────────

  /// Persist a compact JSON of the signed-in user + client for fast hydration.
  static Future<void> writeIdentity(NexusUser user, NexusClient client) {
    final json = jsonEncode({
      'user': user.toJson(),
      'client': client.toJson(),
    });
    return _op((s) => s.write(key: _identityKey, value: json));
  }

  /// Reads the cached identity, or null if absent/corrupt.
  static Future<({NexusUser user, NexusClient client})?> readIdentity() async {
    final raw = await _op((s) => s.read(key: _identityKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final user = NexusUser.fromJson(
            Map<String, dynamic>.from(decoded['user'] as Map));
        final client = NexusClient.fromJson(
            Map<String, dynamic>.from(decoded['client'] as Map));
        return (user: user, client: client);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> deleteIdentity() =>
      _op((s) => s.delete(key: _identityKey));

  // ── Gateway base URL override (optional) ────────────────────────────

  static Future<String?> readGatewayBaseUrl() =>
      _op((s) => s.read(key: _gatewayKey));

  static Future<void> writeGatewayBaseUrl(String url) =>
      _op((s) => s.write(key: _gatewayKey, value: url));

  /// Clear all account credentials on sign-out.
  static Future<void> clear() async {
    await deleteToken();
    await deleteIdentity();
  }
}
