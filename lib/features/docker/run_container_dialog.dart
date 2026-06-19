// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/infrastructure/docker/docker_providers.dart';

/// Dialog to run (`docker run`) a container locally from an image tag. Used both
/// from the Docker tab ("Run container") and from a passed CI build's "Launch
/// via Docker" button — pass [initialImageTag] to pre-fill it.
///
/// Returns the new container id via [Navigator.pop] on success (null on cancel).
class RunContainerDialog extends ConsumerStatefulWidget {
  final String? initialImageTag;
  final String? initialName;

  const RunContainerDialog({super.key, this.initialImageTag, this.initialName});

  /// Convenience: show the dialog and return the new container id (or null).
  static Future<String?> show(
    BuildContext context, {
    String? imageTag,
    String? name,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          RunContainerDialog(initialImageTag: imageTag, initialName: name),
    );
  }

  @override
  ConsumerState<RunContainerDialog> createState() => _RunContainerDialogState();
}

class _RunContainerDialogState extends ConsumerState<RunContainerDialog> {
  late final TextEditingController _image;
  late final TextEditingController _name;
  // Each row is "containerPort:hostPort" (e.g. 8080:8080). One free row always.
  final _ports = <_PortRow>[];
  // Each row is "KEY=VALUE".
  final _envs = <TextEditingController>[];

  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _image = TextEditingController(text: widget.initialImageTag ?? '');
    _name = TextEditingController(text: widget.initialName ?? '');
    _ports.add(_PortRow());
    _envs.add(TextEditingController());
  }

  @override
  void dispose() {
    _image.dispose();
    _name.dispose();
    for (final p in _ports) {
      p.dispose();
    }
    for (final e in _envs) {
      e.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectPorts() {
    final map = <String, String>{};
    for (final row in _ports) {
      final c = row.container.text.trim();
      final h = row.host.text.trim();
      if (c.isEmpty || h.isEmpty) continue;
      map[c] = h;
    }
    return map;
  }

  List<String> _collectEnv() {
    final out = <String>[];
    for (final e in _envs) {
      final v = e.text.trim();
      if (v.isEmpty || !v.contains('=')) continue;
      out.add(v);
    }
    return out;
  }

  Future<void> _run() async {
    final imageTag = _image.text.trim();
    if (imageTag.isEmpty) {
      setState(() => _error = 'An image tag is required.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(dockerEngineClientProvider)
          .runContainer(
            imageTag: imageTag,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            env: _collectEnv(),
            portBindings: _collectPorts(),
          );
      ref.invalidate(dockerContainersProvider);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Run container'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _image,
                autofocus: widget.initialImageTag == null,
                decoration: const InputDecoration(
                  labelText: 'Image tag',
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'my-project:latest',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Container name (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _label('Port mappings  (container : host)'),
              ..._buildPortRows(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add port'),
                onPressed: () => setState(() => _ports.add(_PortRow())),
              ),
              const SizedBox(height: 12),
              _label('Environment  (KEY=VALUE)'),
              ..._buildEnvRows(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add variable'),
                onPressed: () =>
                    setState(() => _envs.add(TextEditingController())),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 16),
          label: const Text('Run'),
          onPressed: _running ? null : _run,
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    ),
  );

  List<Widget> _buildPortRows() {
    return [
      for (var i = 0; i < _ports.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ports[i].container,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '8080',
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(':'),
              ),
              Expanded(
                child: TextField(
                  controller: _ports[i].host,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '8080',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 16),
                onPressed: _ports.length == 1
                    ? null
                    : () => setState(() => _ports.removeAt(i).dispose()),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildEnvRows() {
    return [
      for (var i = 0; i < _envs.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _envs[i],
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'KEY=value',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 16),
                onPressed: _envs.length == 1
                    ? null
                    : () => setState(() => _envs.removeAt(i).dispose()),
              ),
            ],
          ),
        ),
    ];
  }
}

class _PortRow {
  final TextEditingController container = TextEditingController();
  final TextEditingController host = TextEditingController();
  void dispose() {
    container.dispose();
    host.dispose();
  }
}
