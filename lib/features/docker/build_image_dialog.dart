// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/infrastructure/docker/docker_context_tar.dart';
import 'package:nexus_projects_client/infrastructure/docker/docker_models.dart';
import 'package:nexus_projects_client/infrastructure/docker/docker_providers.dart';
import 'package:nexus_projects_client/infrastructure/workspace/workspace_provider.dart';

/// Dialog that builds a Docker image from a project's workspace Dockerfile via
/// the Engine API, streaming the daemon's build log live. The build context is
/// tarred straight out of the SQLite-backed workspace — no host files, so it
/// works inside the macOS App Sandbox.
class BuildImageDialog extends ConsumerStatefulWidget {
  final int projectPk;
  final String projectName;
  const BuildImageDialog({
    super.key,
    required this.projectPk,
    required this.projectName,
  });

  @override
  ConsumerState<BuildImageDialog> createState() => _BuildImageDialogState();
}

class _BuildImageDialogState extends ConsumerState<BuildImageDialog> {
  final _tagCtrl = TextEditingController();
  final _dockerfileCtrl = TextEditingController(text: 'Dockerfile');
  final _scroll = ScrollController();
  final List<DockerBuildEvent> _log = [];

  StreamSubscription<DockerBuildEvent>? _sub;
  bool _building = false;
  bool _done = false;
  bool _hadError = false;

  @override
  void dispose() {
    _sub?.cancel();
    _tagCtrl.dispose();
    _dockerfileCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final tag = _tagCtrl.text.trim();
    final dockerfile = _dockerfileCtrl.text.trim().isEmpty
        ? 'Dockerfile'
        : _dockerfileCtrl.text.trim();
    if (tag.isEmpty) {
      setState(() {
        _log.add(
          const DockerBuildEvent(
            'Image tag is required (e.g. myapp:latest).',
            isError: true,
          ),
        );
      });
      return;
    }

    setState(() {
      _building = true;
      _done = false;
      _hadError = false;
      _log.clear();
      _log.add(
        DockerBuildEvent(
          'Packing "${widget.projectName}" workspace and building "$tag"…',
        ),
      );
    });

    try {
      final ws = await ref.read(workspaceFsProvider(widget.projectPk).future);
      if (!await ws.exists(
        dockerfile.startsWith('/') ? dockerfile : '/$dockerfile',
      )) {
        _append(
          DockerBuildEvent(
            'No Dockerfile found at "$dockerfile" in this workspace.',
            isError: true,
          ),
        );
        setState(() {
          _building = false;
          _done = true;
          _hadError = true;
        });
        return;
      }
      final tar = await const DockerContextTar().fromWorkspace(ws);
      final client = ref.read(dockerEngineClientProvider);
      final dfRel = dockerfile.startsWith('/')
          ? dockerfile.substring(1)
          : dockerfile;

      _sub = client
          .buildImage(contextTar: tar, imageTag: tag, dockerfile: dfRel)
          .listen(
            _append,
            onError: (e) {
              _append(DockerBuildEvent('$e', isError: true));
              setState(() {
                _building = false;
                _done = true;
                _hadError = true;
              });
            },
            onDone: () {
              setState(() {
                _building = false;
                _done = true;
              });
              ref.invalidate(dockerImagesProvider);
            },
          );
    } catch (e) {
      _append(DockerBuildEvent('Build failed to start: $e', isError: true));
      setState(() {
        _building = false;
        _done = true;
        _hadError = true;
      });
    }
  }

  void _append(DockerBuildEvent e) {
    if (!mounted) return;
    setState(() {
      _log.add(e);
      if (e.isError) _hadError = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Build image — ${widget.projectName}'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _tagCtrl,
                    enabled: !_building,
                    decoration: const InputDecoration(
                      labelText: 'Image tag',
                      hintText: 'myapp:latest',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _dockerfileCtrl,
                    enabled: !_building,
                    decoration: const InputDecoration(
                      labelText: 'Dockerfile',
                      hintText: 'Dockerfile',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 320,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _log.isEmpty
                  ? const Center(
                      child: Text(
                        'Build output will appear here.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        itemCount: _log.length,
                        itemBuilder: (c, i) {
                          final e = _log[i];
                          return Text(
                            e.text,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: e.isError
                                  ? const Color(0xFFFF6B6B)
                                  : const Color(0xFFD4D4D4),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _building ? null : () => Navigator.of(context).pop(),
          child: Text(_done ? 'Close' : 'Cancel'),
        ),
        FilledButton.icon(
          onPressed: _building ? null : _start,
          icon: _building
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_done && !_hadError ? Icons.check : Icons.build),
          label: Text(_building ? 'Building…' : (_done ? 'Rebuild' : 'Build')),
        ),
      ],
    );
  }
}
