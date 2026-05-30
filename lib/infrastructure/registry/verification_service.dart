// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import '../database/nexus_database.dart';
import 'registry_client.dart';
import 'registry_models.dart';

/// Resolves the freshness [Verdict] for a package/repo by hitting the registry
/// APIs and applying the deterministic rule in [VerdictX.compute] — the verdict
/// is NEVER produced by the AI. Results are cached in [LibraryVerifications]
/// with a TTL so re-opening the Tag Board is instant and we stay under GitHub's
/// rate limit.
class VerificationService {
  VerificationService({required this.db, required this.client});

  final NexusDatabase db;
  final RegistryClient client;

  /// How long a cached verdict is trusted before we re-check the registry.
  static const cacheTtl = Duration(hours: 24);

  /// Verify [name] in [ecosystem] (`pubdev` | `github`). For pub.dev we resolve
  /// the package's repository and verify that, since commit/archived state lives
  /// on GitHub. [forceRefresh] bypasses the cache.
  Future<VerificationResult> verify({
    required String name,
    required String ecosystem,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await db.getCachedVerification(ecosystem, name);
      if (cached != null &&
          DateTime.now().difference(cached.checkedAt) < cacheTtl) {
        return _fromRow(cached);
      }
    }

    final result = ecosystem == 'pubdev'
        ? await _verifyPubDev(name)
        : await _verifyGithub(name);

    await db.upsertVerification(_toCompanion(result));
    return result;
  }

  Future<VerificationResult> _verifyPubDev(String name) async {
    final pkg = await client.pubDevPackage(name);
    if (pkg == null) {
      return _unknown(ecosystem: 'pubdev', name: name);
    }

    final latest = pkg['latest'] as Map<String, dynamic>?;
    final published = _parseDate(latest?['published'] as String?);
    final pubspec = latest?['pubspec'] as Map<String, dynamic>?;
    final repoUrl =
        (pubspec?['repository'] ?? pubspec?['homepage']) as String?;

    final score = await client.pubDevScore(name);
    final likes = (score?['likeCount'] as num?)?.toInt();

    // If the package points at a GitHub repo, fold in commit/archived state.
    final ownerRepo = _githubOwnerRepo(repoUrl);
    if (ownerRepo != null) {
      final gh = await _fetchGithub(ownerRepo);
      final verdict = VerdictX.compute(
        archived: gh.archived,
        lastRelease: published ?? gh.lastRelease,
        lastCommit: gh.lastCommit,
      );
      return VerificationResult(
        ecosystem: 'pubdev',
        name: name,
        repoUrl: repoUrl,
        lastCommit: gh.lastCommit,
        lastRelease: published ?? gh.lastRelease,
        archived: gh.archived,
        popularity: likes ?? gh.popularity,
        owner: gh.owner,
        verdict: verdict,
        checkedAt: DateTime.now(),
      );
    }

    final verdict = VerdictX.compute(
      archived: false,
      lastRelease: published,
      lastCommit: null,
    );
    return VerificationResult(
      ecosystem: 'pubdev',
      name: name,
      repoUrl: repoUrl,
      lastRelease: published,
      popularity: likes,
      verdict: verdict,
      checkedAt: DateTime.now(),
    );
  }

  Future<VerificationResult> _verifyGithub(String nameOrUrl) async {
    final ownerRepo = _githubOwnerRepo(nameOrUrl) ?? nameOrUrl;
    final gh = await _fetchGithub(ownerRepo);
    if (gh.missing) {
      return _unknown(ecosystem: 'github', name: ownerRepo);
    }
    final verdict = VerdictX.compute(
      archived: gh.archived,
      lastRelease: gh.lastRelease,
      lastCommit: gh.lastCommit,
    );
    return VerificationResult(
      ecosystem: 'github',
      name: ownerRepo,
      repoUrl: 'https://github.com/$ownerRepo',
      lastCommit: gh.lastCommit,
      lastRelease: gh.lastRelease,
      archived: gh.archived,
      popularity: gh.popularity,
      owner: gh.owner,
      verdict: verdict,
      checkedAt: DateTime.now(),
    );
  }

  Future<_GithubFacts> _fetchGithub(String ownerRepo) async {
    final repo = await client.githubRepo(ownerRepo);
    if (repo == null) return const _GithubFacts.missing();

    final release = await client.githubLatestRelease(ownerRepo);
    final commit = await client.githubLatestCommit(ownerRepo);

    return _GithubFacts(
      archived: repo['archived'] as bool? ?? false,
      lastCommit: _parseDate(
        (commit?['commit']?['committer']?['date']) as String?,
      ),
      lastRelease: _parseDate(release?['published_at'] as String?),
      popularity: (repo['stargazers_count'] as num?)?.toInt(),
      owner: (repo['owner']?['login']) as String?,
    );
  }

  VerificationResult _unknown({required String ecosystem, required String name}) {
    return VerificationResult(
      ecosystem: ecosystem,
      name: name,
      verdict: Verdict.unknown,
      checkedAt: DateTime.now(),
    );
  }

  VerificationResult _fromRow(LibraryVerification row) {
    return VerificationResult(
      ecosystem: row.ecosystem,
      name: row.name,
      repoUrl: row.repoUrl,
      lastCommit: row.lastCommit,
      lastRelease: row.lastRelease,
      archived: row.archived,
      popularity: row.popularity,
      owner: row.owner,
      verdict: VerdictX.fromWire(row.verdict),
      checkedAt: row.checkedAt,
    );
  }

  LibraryVerificationsCompanion _toCompanion(VerificationResult r) {
    return LibraryVerificationsCompanion(
      ecosystem: Value(r.ecosystem),
      name: Value(r.name),
      repoUrl: Value(r.repoUrl),
      lastCommit: Value(r.lastCommit),
      lastRelease: Value(r.lastRelease),
      archived: Value(r.archived),
      popularity: Value(r.popularity),
      owner: Value(r.owner),
      verdict: Value(r.verdict.wire),
      checkedAt: Value(r.checkedAt),
    );
  }

  static DateTime? _parseDate(String? s) =>
      s == null ? null : DateTime.tryParse(s);

  /// Extracts `owner/repo` from a GitHub URL, or null for non-GitHub URLs.
  static String? _githubOwnerRepo(String? url) {
    if (url == null) return null;
    final m = RegExp(r'github\.com[/:]([^/]+)/([^/#?]+)').firstMatch(url);
    if (m == null) return null;
    final owner = m.group(1)!;
    var repo = m.group(2)!;
    if (repo.endsWith('.git')) repo = repo.substring(0, repo.length - 4);
    return '$owner/$repo';
  }
}

class _GithubFacts {
  const _GithubFacts({
    this.archived = false,
    this.lastCommit,
    this.lastRelease,
    this.popularity,
    this.owner,
  }) : missing = false;

  const _GithubFacts.missing()
      : archived = false,
        lastCommit = null,
        lastRelease = null,
        popularity = null,
        owner = null,
        missing = true;

  final bool archived;
  final DateTime? lastCommit;
  final DateTime? lastRelease;
  final int? popularity;
  final String? owner;
  final bool missing;
}

final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(
    db: ref.watch(nexusDatabaseProvider),
    client: ref.watch(registryClientProvider),
  );
});
