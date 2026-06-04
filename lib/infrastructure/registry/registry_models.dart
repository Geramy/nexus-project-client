// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Deterministic freshness verdict for a package/repo. Computed from release +
/// commit dates and archived state — never by the AI.
enum Verdict { fresh, aging, stale, dead, unknown }

extension VerdictX on Verdict {
  String get wire => name;
  static Verdict fromWire(String? s) => Verdict.values.firstWhere(
    (v) => v.name == s,
    orElse: () => Verdict.unknown,
  );

  /// Computes the verdict from the inputs, per the project's hard rules:
  ///   archived           → dead
  ///   >24mo (rel & commit) → stale
  ///   12–24mo            → aging
  ///   <12mo              → fresh
  static Verdict compute({
    required bool archived,
    DateTime? lastRelease,
    DateTime? lastCommit,
  }) {
    if (archived) return Verdict.dead;
    final newest = [lastRelease, lastCommit]
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (acc, d) => acc == null || d.isAfter(acc) ? d : acc,
        );
    if (newest == null) return Verdict.unknown;
    final months = DateTime.now().difference(newest).inDays / 30.0;
    if (months > 24) return Verdict.stale;
    if (months >= 12) return Verdict.aging;
    return Verdict.fresh;
  }
}

/// First-party / company-backed GitHub orgs, used for a trust signal on tags.
const Set<String> trustedOrgs = {
  'flutter',
  'dart-lang',
  'google',
  'googleapis',
  'grpc',
  'facebook',
  'meta',
  'microsoft',
  'dotnet',
  'apple',
};

/// The resolved freshness info for one package/repo.
class VerificationResult {
  final String ecosystem; // pubdev | github
  final String name;
  final String? repoUrl;
  final DateTime? lastCommit;
  final DateTime? lastRelease;
  final bool archived;
  final int? popularity;
  final String? owner;
  final Verdict verdict;
  final DateTime checkedAt;

  const VerificationResult({
    required this.ecosystem,
    required this.name,
    required this.verdict,
    required this.checkedAt,
    this.repoUrl,
    this.lastCommit,
    this.lastRelease,
    this.archived = false,
    this.popularity,
    this.owner,
  });

  bool get isTrusted =>
      owner != null && trustedOrgs.contains(owner!.toLowerCase());
}
