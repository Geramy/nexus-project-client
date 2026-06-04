// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'github_token_store.dart';

/// Thin HTTP client over the public package/repo registries we trust for the
/// freshness check: GitHub REST + pub.dev. No verdict logic lives here — it
/// only fetches + decodes JSON. [VerificationService] interprets the results.
///
/// GitHub's unauthenticated REST limit is 60 req/hr; if a PAT is configured in
/// [GithubTokenStore] it is sent as a Bearer token (5000 req/hr).
class RegistryClient {
  RegistryClient({required this.tokenStore, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final GithubTokenStore tokenStore;
  final http.Client _http;

  static const _ghBase = 'https://api.github.com';
  static const _pubBase = 'https://pub.dev';

  Future<Map<String, String>> _githubHeaders() async {
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'nexus-projects-client',
    };
    final token = await tokenStore.read();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<dynamic> _getJson(Uri uri, {Map<String, String>? headers}) async {
    final res = await _http.get(uri, headers: headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RegistryException(
        'GET ${uri.path} failed (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  // ==================== pub.dev ====================

  /// Package metadata incl. `latest.published` and `latest.pubspec`.
  Future<Map<String, dynamic>?> pubDevPackage(String name) async {
    final json = await _getJson(Uri.parse('$_pubBase/api/packages/$name'));
    return json as Map<String, dynamic>?;
  }

  /// Score/popularity card: `likeCount`, `grantedPoints`, `popularityScore`.
  Future<Map<String, dynamic>?> pubDevScore(String name) async {
    final json = await _getJson(
      Uri.parse('$_pubBase/api/packages/$name/score'),
    );
    return json as Map<String, dynamic>?;
  }

  /// Package search; returns the raw `packages` list (each `{package: name}`).
  Future<List<String>> pubDevSearch(String query) async {
    final json = await _getJson(
      Uri.parse('$_pubBase/api/search?q=${Uri.encodeQueryComponent(query)}'),
    );
    final packages = (json as Map<String, dynamic>?)?['packages'] as List?;
    if (packages == null) return const [];
    return packages
        .map((p) => (p as Map<String, dynamic>)['package'] as String?)
        .whereType<String>()
        .toList();
  }

  // ==================== GitHub ====================

  /// Repo metadata: `pushed_at`, `archived`, `stargazers_count`, `owner.login`.
  /// [ownerRepo] is `owner/repo`.
  Future<Map<String, dynamic>?> githubRepo(String ownerRepo) async {
    final json = await _getJson(
      Uri.parse('$_ghBase/repos/$ownerRepo'),
      headers: await _githubHeaders(),
    );
    return json as Map<String, dynamic>?;
  }

  /// Latest published release (`published_at`, `tag_name`). Null if none.
  Future<Map<String, dynamic>?> githubLatestRelease(String ownerRepo) async {
    final json = await _getJson(
      Uri.parse('$_ghBase/repos/$ownerRepo/releases/latest'),
      headers: await _githubHeaders(),
    );
    return json as Map<String, dynamic>?;
  }

  /// Most recent commit on the default branch (`commit.committer.date`).
  Future<Map<String, dynamic>?> githubLatestCommit(String ownerRepo) async {
    final json = await _getJson(
      Uri.parse('$_ghBase/repos/$ownerRepo/commits?per_page=1'),
      headers: await _githubHeaders(),
    );
    final list = json as List?;
    if (list == null || list.isEmpty) return null;
    return list.first as Map<String, dynamic>;
  }

  /// Repo search sorted by stars; returns `owner/repo` full names.
  Future<List<String>> githubSearch(String query) async {
    final json = await _getJson(
      Uri.parse(
        '$_ghBase/search/repositories?q=${Uri.encodeQueryComponent(query)}'
        '&sort=stars&order=desc&per_page=10',
      ),
      headers: await _githubHeaders(),
    );
    final items = (json as Map<String, dynamic>?)?['items'] as List?;
    if (items == null) return const [];
    return items
        .map((i) => (i as Map<String, dynamic>)['full_name'] as String?)
        .whereType<String>()
        .toList();
  }

  void close() => _http.close();
}

class RegistryException implements Exception {
  RegistryException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  /// GitHub returns 403 when the rate limit is exhausted.
  bool get isRateLimited => statusCode == 403 || statusCode == 429;

  @override
  String toString() => 'RegistryException: $message';
}

final registryClientProvider = Provider<RegistryClient>((ref) {
  final client = RegistryClient(
    tokenStore: ref.watch(githubTokenStoreProvider),
  );
  ref.onDispose(client.close);
  return client;
});
