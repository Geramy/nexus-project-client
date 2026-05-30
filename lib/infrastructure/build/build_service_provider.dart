// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/database_provider.dart';
import 'build_service.dart';

/// The app's single [BuildService], wired to the shared database. Backends use
/// their defaults (local Docker CLI + local workflow runner); a remote build
/// server can be attached later when one is configured.
final buildServiceProvider = Provider<BuildService>((ref) {
  final db = ref.watch(nexusDatabaseProvider);
  return BuildService(db: db);
});
