// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

// Lightweight value types mirroring the Docker Engine REST API JSON shapes we
// consume. Only the fields the UI actually shows are parsed.

class DockerVersion {
  final String version;
  final String apiVersion;
  final String os;
  final String arch;

  const DockerVersion({
    required this.version,
    required this.apiVersion,
    required this.os,
    required this.arch,
  });

  factory DockerVersion.fromJson(Map<String, dynamic> j) => DockerVersion(
        version: '${j['Version'] ?? '?'}',
        apiVersion: '${j['ApiVersion'] ?? '?'}',
        os: '${j['Os'] ?? '?'}',
        arch: '${j['Arch'] ?? '?'}',
      );
}

class DockerImage {
  /// Full image id, e.g. `sha256:abcd...`.
  final String id;

  /// Tags like `myapp:latest`. Untagged images report `<none>:<none>`.
  final List<String> repoTags;

  /// Size in bytes.
  final int size;

  /// Creation time (unix seconds).
  final int created;

  const DockerImage({
    required this.id,
    required this.repoTags,
    required this.size,
    required this.created,
  });

  factory DockerImage.fromJson(Map<String, dynamic> j) {
    final tags = (j['RepoTags'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    return DockerImage(
      id: '${j['Id'] ?? ''}',
      repoTags: tags.isEmpty ? const ['<none>:<none>'] : tags,
      size: (j['Size'] as num?)?.toInt() ?? 0,
      created: (j['Created'] as num?)?.toInt() ?? 0,
    );
  }

  /// Short id (12 hex chars) without the `sha256:` prefix.
  String get shortId {
    final raw = id.startsWith('sha256:') ? id.substring(7) : id;
    return raw.length >= 12 ? raw.substring(0, 12) : raw;
  }

  String get primaryTag => repoTags.isNotEmpty ? repoTags.first : '<none>:<none>';
}

class DockerContainer {
  final String id;
  final List<String> names;
  final String image;

  /// `running`, `exited`, `created`, `paused`, etc.
  final String state;

  /// Human status line, e.g. `Up 3 minutes`.
  final String status;

  const DockerContainer({
    required this.id,
    required this.names,
    required this.image,
    required this.state,
    required this.status,
  });

  factory DockerContainer.fromJson(Map<String, dynamic> j) {
    final names = (j['Names'] as List?)?.map((e) => '$e'.replaceFirst('/', '')).toList() ?? const <String>[];
    return DockerContainer(
      id: '${j['Id'] ?? ''}',
      names: names,
      image: '${j['Image'] ?? ''}',
      state: '${j['State'] ?? ''}',
      status: '${j['Status'] ?? ''}',
    );
  }

  String get shortId => id.length >= 12 ? id.substring(0, 12) : id;
  String get name => names.isNotEmpty ? names.first : shortId;
  bool get isRunning => state.toLowerCase() == 'running';
}

/// One decoded line from a `POST /build` progress stream.
class DockerBuildEvent {
  final String text;
  final bool isError;
  const DockerBuildEvent(this.text, {this.isError = false});
}
