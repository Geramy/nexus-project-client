// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io' show Platform;

/// Models + helpers for the in-app updater: a parsed GitHub release, the
/// per-OS installer asset the running platform needs, and a tiny semantic
/// version comparator (we avoid pulling in `pub_semver` for three integers).

/// One downloadable file attached to a GitHub release.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.sizeBytes,
  });

  final String name;
  final String url;
  final int sizeBytes;
}

/// A GitHub release distilled to what the updater needs.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.notesUrl,
    required this.publishedAt,
    required this.assets,
  });

  /// Raw tag, e.g. `v1.8.0`.
  final String tag;

  /// Parsed semantic version of [tag] (leading `v` stripped).
  final SemVer version;

  /// `html_url` of the release — opened by the "What's new" action.
  final String notesUrl;

  final DateTime? publishedAt;
  final List<UpdateAsset> assets;

  /// The installer asset for the CURRENT platform, or null if this release has
  /// none (e.g. an unsupported OS, or an incomplete release).
  UpdateAsset? assetForThisPlatform() {
    final suffix = PlatformTarget.current?.assetSuffix;
    if (suffix == null) return null;
    for (final a in assets) {
      if (a.name.toLowerCase().endsWith(suffix)) return a;
    }
    return null;
  }

  /// The published `SHA256SUMS.txt` asset, if present.
  UpdateAsset? checksumsAsset() {
    for (final a in assets) {
      if (a.name == PlatformTarget.checksumsAssetName) return a;
    }
    return null;
  }
}

/// Resolves the running desktop platform to the release-asset naming the CI
/// publishes (see `.github/workflows/build.yml`). Mobile/web/unsupported → null.
enum PlatformTarget {
  macos('-macos.pkg'),
  windows('-windows-setup.exe'),
  // CI publishes both a .deb and a portable .tar.gz; we prefer the .deb and
  // hand it to the graphical package installer.
  linux('-linux-amd64.deb');

  const PlatformTarget(this.assetSuffix);

  /// The lowercase filename suffix that identifies this platform's installer.
  final String assetSuffix;

  /// The checksums manifest attached to every release (platform-agnostic).
  static const String checksumsAssetName = 'SHA256SUMS.txt';

  /// The target for the OS we're running on, or null if updates aren't
  /// supported here (iOS/Android/web).
  static PlatformTarget? get current {
    if (Platform.isMacOS) return PlatformTarget.macos;
    if (Platform.isWindows) return PlatformTarget.windows;
    if (Platform.isLinux) return PlatformTarget.linux;
    return null;
  }
}

/// Minimal semantic version: `major.minor.patch` with an optional pre-release
/// label and ignored `+build` metadata. Enough to answer "is the release newer
/// than what's installed?" without a dependency.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch, {this.preRelease});

  final int major;
  final int minor;
  final int patch;

  /// The bit after `-` (e.g. `beta.1`), or null for a final release. A
  /// pre-release sorts BELOW the same major.minor.patch without one.
  final String? preRelease;

  bool get isPreRelease => preRelease != null && preRelease!.isNotEmpty;

  /// Parses `1.8.0`, `v1.8.0`, `1.8.0+24`, `v1.8.0-beta.1`. Returns null if the
  /// core `major.minor.patch` can't be read.
  static SemVer? tryParse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s[0] == 'v' || s[0] == 'V') s = s.substring(1);
    // Drop build metadata.
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    // Split off pre-release.
    String? pre;
    final dash = s.indexOf('-');
    if (dash >= 0) {
      pre = s.substring(dash + 1);
      s = s.substring(0, dash);
    }
    final parts = s.split('.');
    if (parts.isEmpty) return null;
    final major = int.tryParse(parts[0]);
    if (major == null) return null;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    final patch = parts.length > 2 ? int.tryParse(parts[2]) : 0;
    if (minor == null || patch == null) return null;
    return SemVer(
      major,
      minor,
      patch,
      preRelease: (pre != null && pre.isEmpty) ? null : pre,
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Equal core: a pre-release is LOWER than a final release.
    if (isPreRelease && !other.isPreRelease) return -1;
    if (!isPreRelease && other.isPreRelease) return 1;
    if (isPreRelease && other.isPreRelease) {
      return preRelease!.compareTo(other.preRelease!);
    }
    return 0;
  }

  bool isNewerThan(SemVer other) => compareTo(other) > 0;

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return isPreRelease ? '$core-$preRelease' : core;
  }
}
