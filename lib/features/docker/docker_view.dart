// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/docker/docker_models.dart';
import 'package:nexus_projects_client/infrastructure/docker/docker_providers.dart';
import 'build_image_dialog.dart';
import 'run_container_dialog.dart';

/// Global Docker control panel: shows the daemon connection, its images and
/// containers, and lets you build an image from a project's Dockerfile. All of
/// it talks to the Docker Engine API over TCP (sandbox-safe — no CLI).
class DockerView extends ConsumerWidget {
  const DockerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(dockerVersionProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  ref.invalidate(dockerVersionProvider);
                  ref.invalidate(dockerImagesProvider);
                  ref.invalidate(dockerContainersProvider);
                },
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Run container'),
                onPressed: () => RunContainerDialog.show(context),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.build, size: 16),
                label: const Text('Build image'),
                onPressed: () => _openBuildDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ConnectionBanner(
            versionAsync: versionAsync,
            onEditEndpoint: () => _editEndpoint(context, ref),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: versionAsync.hasError
                ? _UnreachableHelp(endpoint: ref.watch(dockerEndpointProvider))
                : ListView(
                    children: const [
                      _ImagesSection(),
                      SizedBox(height: 24),
                      _ContainersSection(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBuildDialog(BuildContext context, WidgetRef ref) async {
    final projectPk = ref.read(currentProjectIdProvider);
    final db = ref.read(nexusDatabaseProvider);
    final project = await db.getProjectById(projectPk);
    if (!context.mounted) return;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a project first — its workspace provides the build context.',
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) =>
          BuildImageDialog(projectPk: projectPk, projectName: project.name),
    );
  }

  Future<void> _editEndpoint(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: ref.read(dockerEndpointProvider));
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Docker Engine endpoint'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Docker daemon endpoint. Defaults to the native transport:\n'
              '  • macOS / Linux:  unix:///var/run/docker.sock\n'
              '  • Windows:  npipe:////./pipe/docker_engine\n'
              'Or point at a TCP daemon, e.g. http://localhost:2375.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'unix:///var/run/docker.sock',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      ref.read(dockerEndpointProvider.notifier).state = result;
    }
  }
}

class _ConnectionBanner extends StatelessWidget {
  final AsyncValue<DockerVersion> versionAsync;
  final VoidCallback onEditEndpoint;
  const _ConnectionBanner({
    required this.versionAsync,
    required this.onEditEndpoint,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon, text) = switch (versionAsync) {
      AsyncData(:final value) => (
        Colors.green,
        Icons.check_circle,
        'Connected • Docker ${value.version} (API ${value.apiVersion}) • ${value.os}/${value.arch}',
      ),
      AsyncError() => (
        Colors.red,
        Icons.error_outline,
        'Cannot reach the Docker daemon.',
      ),
      _ => (Colors.orange, Icons.hourglass_empty, 'Connecting…'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onEditEndpoint, child: const Text('Endpoint')),
        ],
      ),
    );
  }
}

class _UnreachableHelp extends StatelessWidget {
  final String endpoint;
  const _UnreachableHelp({required this.endpoint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'Docker daemon not reachable',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 460,
            child: Text(
              'Tried $endpoint. Make sure Docker is running (OrbStack or Docker '
              'Desktop on macOS/Windows, the docker daemon on Linux). If your '
              'daemon listens elsewhere, set the endpoint via the Endpoint '
              'button and refresh.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagesSection extends ConsumerWidget {
  const _ImagesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagesAsync = ref.watch(dockerImagesProvider);
    return _Section(
      title: 'Images',
      child: imagesAsync.when(
        data: (images) {
          if (images.isEmpty)
            return const _EmptyRow('No images on this daemon.');
          return Column(
            children: images.map((img) => _ImageTile(image: img)).toList(),
          );
        },
        loading: () => const _LoadingRow(),
        error: (e, _) => _EmptyRow('Error: $e'),
      ),
    );
  }
}

class _ImageTile extends ConsumerWidget {
  final DockerImage image;
  const _ImageTile({required this.image});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.layers_outlined),
        title: Text(
          image.primaryTag,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${image.shortId} • ${_fmtSize(image.size)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Run container',
              icon: const Icon(Icons.play_circle_outline, size: 18),
              onPressed: image.primaryTag.startsWith('<none>')
                  ? null
                  : () =>
                        RunContainerDialog.show(context, imageTag: image.primaryTag),
            ),
            IconButton(
              tooltip: 'Remove image',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
            try {
              await ref
                  .read(dockerEngineClientProvider)
                  .removeImage(
                    image.primaryTag.startsWith('<none>')
                        ? image.id
                        : image.primaryTag,
                    force: true,
                  );
              ref.invalidate(dockerImagesProvider);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
              }
            }
          },
            ),
          ],
        ),
      ),
    );
  }
}

class _ContainersSection extends ConsumerWidget {
  const _ContainersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final containersAsync = ref.watch(dockerContainersProvider);
    return _Section(
      title: 'Containers',
      child: containersAsync.when(
        data: (containers) {
          if (containers.isEmpty) return const _EmptyRow('No containers.');
          return Column(
            children: containers
                .map((c) => _ContainerTile(container: c))
                .toList(),
          );
        },
        loading: () => const _LoadingRow(),
        error: (e, _) => _EmptyRow('Error: $e'),
      ),
    );
  }
}

class _ContainerTile extends ConsumerWidget {
  final DockerContainer container;
  const _ContainerTile({required this.container});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = container.isRunning;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.inventory_2_outlined,
          color: running ? Colors.green : Colors.grey,
        ),
        title: Text(
          container.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${container.image} • ${container.status}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: running ? 'Stop' : 'Start',
              icon: Icon(
                running
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                size: 18,
              ),
              onPressed: () async {
                final client = ref.read(dockerEngineClientProvider);
                try {
                  if (running) {
                    await client.stopContainer(container.id);
                  } else {
                    await client.startContainer(container.id);
                  }
                  ref.invalidate(dockerContainersProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Action failed: $e')),
                    );
                  }
                }
              },
            ),
            IconButton(
              tooltip: 'Remove container',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () async {
                try {
                  await ref
                      .read(dockerEngineClientProvider)
                      .removeContainer(container.id, force: true);
                  ref.invalidate(dockerContainersProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Remove failed: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  const _EmptyRow(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12)),
  );
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(12),
    child: SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

String _fmtSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
