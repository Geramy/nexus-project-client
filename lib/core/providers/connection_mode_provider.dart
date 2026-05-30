// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_mode_provider.g.dart';

enum ConnectionMode { local, remote, hybrid }

@riverpod
class ConnectionModeNotifier extends _$ConnectionModeNotifier {
  @override
  ConnectionMode build() => ConnectionMode.local;

  void setMode(ConnectionMode mode) {
    state = mode;
  }
}
