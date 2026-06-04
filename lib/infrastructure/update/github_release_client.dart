// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_models.dart';

/// Raised when the latest release can't be fetched (network, rate limit, or an
/// unexpected GitHub response). The auto-check path swallows this; the manual
/// "Check for updates" button surfaces [message] to the user.
class ReleaseLookupException implements Exception {
  ReleaseLookupException(this.message);
  final String message;
  @override
  String toString() => 'ReleaseLookupException: $message';
}

/// Reads the latest published release from the project's PUBLIC GitHub repo.
/// Public means no token is required — anonymous calls work (rate-limited to
/// 60/hr/IP, which is ample for a once-per-launch check).
class GithubReleaseClient {
  GithubReleaseClient({http.Client? client, this.repoSlug = _defaultSlug})
    : _client = client ?? http.Client();

  static const _defaultSlug = 'Geramy/nexus-project-client';

  final http.Client _client;
  final String repoSlug;

  /// Fetches the latest NON-prerelease, non-draft release. GitHub's
  /// `/releases/latest` endpoint already excludes both. Returns the parsed
  /// release, or throws [ReleaseLookupException].
  Future<AppRelease> fetchLatest() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repoSlug/releases/latest',
    );
    http.Response resp;
    try {
      resp = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
    } catch (e) {
      throw ReleaseLookupException('Network error: $e');
    }

    if (resp.statusCode == 403 || resp.statusCode == 429) {
      throw ReleaseLookupException(
        'GitHub rate limit reached — try again later.',
      );
    }
    if (resp.statusCode != 200) {
      throw ReleaseLookupException(
        'Unexpected response from GitHub (${resp.statusCode}).',
      );
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ReleaseLookupException('Could not parse the release feed.');
    }

    final tag = (json['tag_name'] ?? '').toString();
    final version = SemVer.tryParse(tag);
    if (version == null) {
      throw ReleaseLookupException(
        'Release has an unreadable version ("$tag").',
      );
    }

    final assets = <UpdateAsset>[];
    for (final a in (json['assets'] as List? ?? const [])) {
      if (a is! Map) continue;
      final name = (a['name'] ?? '').toString();
      final url = (a['browser_download_url'] ?? '').toString();
      if (name.isEmpty || url.isEmpty) continue;
      assets.add(
        UpdateAsset(
          name: name,
          url: url,
          sizeBytes: (a['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return AppRelease(
      tag: tag,
      version: version,
      notesUrl: (json['html_url'] ?? 'https://github.com/$repoSlug/releases')
          .toString(),
      publishedAt: DateTime.tryParse((json['published_at'] ?? '').toString()),
      assets: assets,
    );
  }

  void dispose() => _client.close();
}
