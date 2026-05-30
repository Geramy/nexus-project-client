// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

class Project {
  final String id;
  final String name;
  final String? description;
  final String connectionMode;
  final List<String> linkedFolderPaths;

  const Project({
    required this.id,
    required this.name,
    this.description,
    required this.connectionMode,
    this.linkedFolderPaths = const [],
  });
}
