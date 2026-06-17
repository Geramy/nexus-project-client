// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'docker_engine_client.dart';
import 'docker_models.dart';

/// The Docker Engine API endpoint, defaulted to each platform's native daemon
/// transport (the app is no longer sandboxed, so it talks to Docker directly —
/// no TCP bridge):
///   - Windows: `npipe:////./pipe/docker_engine` (Docker Desktop named pipe).
///   - macOS / Linux: `unix:///var/run/docker.sock` (OrbStack/Docker Desktop).
/// Override with any `http://host:port` if the daemon is exposed over TCP.
/// Editable from the Docker view; persistence can be layered on later.
final dockerEndpointProvider = StateProvider<String>(
  (ref) => Platform.isWindows
      ? 'npipe:////./pipe/docker_engine'
      : 'unix:///var/run/docker.sock',
);

/// The shared [DockerEngineClient], rebuilt whenever the endpoint changes.
final dockerEngineClientProvider = Provider<DockerEngineClient>((ref) {
  final endpoint = ref.watch(dockerEndpointProvider);
  final client = DockerEngineClient(baseUrl: endpoint);
  ref.onDispose(client.close);
  return client;
});

/// Daemon version, or an error if it can't be reached. Watch this for the
/// connection-status banner.
final dockerVersionProvider = FutureProvider.autoDispose<DockerVersion>((ref) {
  return ref.watch(dockerEngineClientProvider).version();
});

final dockerImagesProvider = FutureProvider.autoDispose<List<DockerImage>>((
  ref,
) {
  return ref.watch(dockerEngineClientProvider).listImages();
});

final dockerContainersProvider =
    FutureProvider.autoDispose<List<DockerContainer>>((ref) {
      return ref.watch(dockerEngineClientProvider).listContainers(all: true);
    });
