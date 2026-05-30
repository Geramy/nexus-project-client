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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/nexus_account_models.dart';

class NexusAccountStore {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // macOS: use the legacy file-based keychain. The modern data-protection
    // keychain requires a keychain-access-groups entitlement, which can't be
    // carried by Flutter's ad-hoc-signed debug builds (it triggers a launch
    // SIGKILL). The legacy keychain needs no entitlement and works in both
    // debug and signed release builds. Was failing with errSecMissingEntitlement
    // (-34018) before this.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  static const _tokenKey = 'nexus/account_token';
  static const _identityKey = 'nexus/account_identity';
  static const _gatewayKey = 'nexus/gateway_base_url';

  // ── Token ───────────────────────────────────────────────────────────

  static Future<String?> readToken() => _store.read(key: _tokenKey);

  static Future<void> writeToken(String token) =>
      _store.write(key: _tokenKey, value: token);

  static Future<void> deleteToken() => _store.delete(key: _tokenKey);

  // ── Cached identity (user + client) ─────────────────────────────────

  /// Persist a compact JSON of the signed-in user + client for fast hydration.
  static Future<void> writeIdentity(NexusUser user, NexusClient client) {
    final json = jsonEncode({
      'user': user.toJson(),
      'client': client.toJson(),
    });
    return _store.write(key: _identityKey, value: json);
  }

  /// Reads the cached identity, or null if absent/corrupt.
  static Future<({NexusUser user, NexusClient client})?> readIdentity() async {
    final raw = await _store.read(key: _identityKey);
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

  static Future<void> deleteIdentity() => _store.delete(key: _identityKey);

  // ── Gateway base URL override (optional) ────────────────────────────

  static Future<String?> readGatewayBaseUrl() => _store.read(key: _gatewayKey);

  static Future<void> writeGatewayBaseUrl(String url) =>
      _store.write(key: _gatewayKey, value: url);

  /// Clear all account credentials on sign-out.
  static Future<void> clear() async {
    await deleteToken();
    await deleteIdentity();
  }
}
