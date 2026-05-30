// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Simple UI model for Client (for use in providers and sidebar during DB stabilization).
class Client {
  final String id;
  final String name;
  final bool isDefault;

  const Client({
    required this.id,
    required this.name,
    this.isDefault = false,
  });
}