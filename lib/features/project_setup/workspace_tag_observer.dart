// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:yaml/yaml.dart';

import '../../infrastructure/database/nexus_database.dart' hide ProjectTag;
import '../../infrastructure/workspace/workspace.dart';
import 'models/project_tag.dart';
import 'models/tag_category.dart';
import 'providers/tag_providers.dart';

/// Observes the real project workspace and turns hard facts (dependency
/// manifests, Dockerfiles) into tags. Unlike AI proposals, observed tags are
/// facts: `source: workspace`, `status: accepted`. They keep the profile honest
/// as the codebase evolves — the resolver/board always reflects what's actually
/// in the tree.
class WorkspaceTagObserver {
  WorkspaceTagObserver({required this.workspace, required this.db});

  final Workspace workspace;
  final NexusDatabase db;

  /// Scan known manifests and upsert the languages/frameworks/libraries they
  /// imply. Returns the number of tags written. Safe to call repeatedly (the
  /// DAO dedups on project+category+value).
  Future<int> scan(int projectPk) async {
    final controller = TagController(db, projectPk);
    final found = <_Observed>{};

    await _pubspec(found);
    await _cargo(found);
    await _packageJson(found);
    await _csproj(found);
    await _dockerfile(found);

    for (final o in found) {
      await controller.upsert(ProjectTag(
        category: o.category.wire,
        value: o.value,
        source: TagSource.workspace,
        origin: 'workspace',
        status: TagStatus.accepted,
        layerKey: o.layerKey,
        rationale: o.rationale,
      ));
    }
    return found.length;
  }

  Future<String?> _read(String path) async {
    try {
      if (!await workspace.exists(path)) return null;
      return await workspace.readString(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pubspec(Set<_Observed> out) async {
    final content = await _read('/pubspec.yaml');
    if (content == null) return;
    out.add(const _Observed(TagCategory.languages, 'Dart', layerKey: 'client'));
    out.add(const _Observed(TagCategory.frameworks, 'Flutter', layerKey: 'client'));
    try {
      final doc = loadYaml(content);
      final deps = doc is YamlMap ? doc['dependencies'] : null;
      if (deps is YamlMap) {
        for (final key in deps.keys) {
          final name = key.toString();
          if (name == 'flutter' || name == 'flutter_test') continue;
          out.add(_Observed(TagCategory.libraries, name,
              layerKey: 'client', rationale: 'In pubspec.yaml dependencies.'));
        }
      }
    } catch (_) {}
  }

  Future<void> _cargo(Set<_Observed> out) async {
    final content = await _read('/Cargo.toml');
    if (content == null) return;
    out.add(const _Observed(TagCategory.languages, 'Rust', layerKey: 'module'));
    // Lightweight [dependencies] section parse (avoids a TOML dep).
    final lines = content.split('\n');
    var inDeps = false;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inDeps = line == '[dependencies]';
        continue;
      }
      if (!inDeps || line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final name = line.substring(0, eq).trim();
      if (name.isNotEmptyName) {
        out.add(_Observed(TagCategory.libraries, name,
            layerKey: 'module', rationale: 'In Cargo.toml [dependencies].'));
      }
    }
  }

  Future<void> _packageJson(Set<_Observed> out) async {
    final content = await _read('/package.json');
    if (content == null) return;
    out.add(const _Observed(TagCategory.languages, 'TypeScript', layerKey: 'client'));
  }

  Future<void> _csproj(Set<_Observed> out) async {
    // Any *.csproj at the root implies C#.
    try {
      final entries = await workspace.walk(from: '/', maxEntries: 2000);
      final hasCsproj = entries.any((e) => e.name.endsWith('.csproj'));
      if (hasCsproj) {
        out.add(const _Observed(TagCategory.languages, 'C#', layerKey: 'server'));
        out.add(const _Observed(TagCategory.frameworks, 'ASP.NET Core',
            layerKey: 'server'));
      }
    } catch (_) {}
  }

  Future<void> _dockerfile(Set<_Observed> out) async {
    final content = await _read('/Dockerfile');
    if (content == null) return;
    out.add(const _Observed(TagCategory.platforms, 'Cloud / Server',
        rationale: 'Dockerfile present.'));
  }
}

class _Observed {
  const _Observed(this.category, this.value, {this.layerKey, this.rationale});
  final TagCategory category;
  final String value;
  final String? layerKey;
  final String? rationale;

  @override
  bool operator ==(Object other) =>
      other is _Observed &&
      other.category == category &&
      other.value == value;

  @override
  int get hashCode => Object.hash(category, value);
}

extension _NameCheck on String {
  bool get isNotEmptyName =>
      isNotEmpty && RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(this);
}
