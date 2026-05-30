// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Admin console models tab.
/// Ported from ~/IdeaProjects/lemonade_mobile/lib/widgets/admin/admin_models_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/features/ai_providers/providers/admin_console_provider.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/api/types/model_info.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/api/endpoints/admin_endpoint.dart';

/// Models tab with pull, load, unload, and delete actions.
class AdminModelsTab extends ConsumerStatefulWidget {
  const AdminModelsTab({super.key});

  @override
  ConsumerState<AdminModelsTab> createState() => _AdminModelsTabState();
}

class _AdminModelsTabState extends ConsumerState<AdminModelsTab> {
  List<ApiModelInfo> _models = const [];
  Set<String> _loaded = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(adminConsoleClientProvider);
      if (client == null) return;
      final list = await client.models.all();
      final health = await client.admin.health();
      final loaded = (health['all_models_loaded'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => (m['model_name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _models = list;
        _loaded = loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _load(String modelName) async {
    final client = ref.read(adminConsoleClientProvider);
    if (client == null) return;
    _busySnack('Loading $modelName…');
    try {
      await client.admin.load(modelName: modelName);
    } catch (e) {
      _errorSnack('Load failed: $e');
    } finally {
      await _refresh();
    }
  }

  Future<void> _unload(String modelName) async {
    final client = ref.read(adminConsoleClientProvider);
    if (client == null) return;
    _busySnack('Unloading $modelName…');
    try {
      await client.admin.unload(modelName: modelName);
    } catch (e) {
      _errorSnack('Unload failed: $e');
    } finally {
      await _refresh();
    }
  }

  Future<void> _delete(String modelName) async {
    final ok = await _confirm('Delete $modelName?',
        'This removes the model from local storage on the server. Cannot be undone.');
    if (!ok) return;
    final client = ref.read(adminConsoleClientProvider);
    if (client == null) return;
    try {
      await client.admin.delete(modelName: modelName);
    } catch (e) {
      _errorSnack('Delete failed: $e');
    } finally {
      await _refresh();
    }
  }

  Future<void> _pull() async {
    final spec = await _showPullDialog();
    if (spec == null) return;
    final client = ref.read(adminConsoleClientProvider);
    if (client == null) return;

    final progress = ValueNotifier<double?>(null);
    final status = ValueNotifier<String>('Starting…');

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Pulling ${spec.modelName}'),
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, s, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double?>(
                valueListenable: progress,
                builder: (_, p, __) => LinearProgressIndicator(value: p),
              ),
              const SizedBox(height: 12),
              Text(s),
            ],
          ),
        ),
      ),
    );

    try {
      await for (final ev in client.admin.pullStream(
        modelName: spec.modelName,
        checkpoint: spec.checkpoint,
        recipe: spec.recipe,
      )) {
        switch (ev) {
          case PullProgress():
            if (ev.percent != null) progress.value = ev.percent! / 100.0;
            status.value = '${ev.file ?? "Downloading"} (${ev.percent?.toStringAsFixed(0) ?? "?"}%)';
          case PullComplete():
            status.value = 'Complete';
          case PullError():
            status.value = 'Error: ${ev.message}';
        }
      }
    } catch (e) {
      status.value = 'Error: $e';
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _refresh();
    }
  }

  void _busySnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
    );
  }

  void _errorSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.redAccent),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    return res ?? false;
  }

  Future<_PullSpec?> _showPullDialog() async {
    final modelName = TextEditingController();
    final checkpoint = TextEditingController();
    final recipe = TextEditingController(text: 'llamacpp');
    return showDialog<_PullSpec>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pull a model'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: modelName,
                decoration: const InputDecoration(
                  labelText: 'Model name',
                  helperText: 'For HuggingFace pulls use the user.* namespace',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: checkpoint,
                decoration: const InputDecoration(
                  labelText: 'HF checkpoint (optional)',
                  hintText: 'e.g. unsloth/Qwen3-8B-GGUF:Q4_K_M',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: recipe,
                decoration: const InputDecoration(labelText: 'Recipe'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (modelName.text.trim().isEmpty) return;
              Navigator.pop(
                ctx,
                _PullSpec(
                  modelName: modelName.text.trim(),
                  checkpoint: checkpoint.text.trim().isEmpty ? null : checkpoint.text.trim(),
                  recipe: checkpoint.text.trim().isEmpty ? null : recipe.text.trim(),
                ),
              );
            },
            child: const Text('Pull'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pull,
        icon: const Icon(Icons.download),
        label: const Text('Pull'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading && _models.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final m in _models)
                        _ModelTile(
                          model: m,
                          loaded: _loaded.contains(m.id),
                          onLoad: () => _load(m.id),
                          onUnload: () => _unload(m.id),
                          onDelete: () => _delete(m.id),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _PullSpec {
  final String modelName;
  final String? checkpoint;
  final String? recipe;
  _PullSpec({required this.modelName, this.checkpoint, this.recipe});
}

class _ModelTile extends StatelessWidget {
  final ApiModelInfo model;
  final bool loaded;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onDelete;

  const _ModelTile({
    required this.model,
    required this.loaded,
    required this.onLoad,
    required this.onUnload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final installed = model.downloaded == true;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              model.isCollection ? Icons.collections_bookmark : Icons.memory,
              color: loaded ? Colors.green : scheme.outline,
            ),
            title: Text(model.id, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (model.labels.isNotEmpty) model.labels.join(', '),
                if (model.recipe != null) model.recipe!,
                if (loaded) 'loaded',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: _buildTrailing(installed: installed),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing({required bool installed}) {
    if (!installed) {
      return TextButton.icon(
        onPressed: () {}, // Inline pull not wired (no modelDownloadsProvider in this project)
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Download'),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _InstalledPill(),
        PopupMenuButton<String>(
          onSelected: (action) {
            switch (action) {
              case 'load':
                onLoad();
              case 'unload':
                onUnload();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => [
            if (!loaded) const PopupMenuItem(value: 'load', child: Text('Load')),
            if (loaded) const PopupMenuItem(value: 'unload', child: Text('Unload')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }
}

class _InstalledPill extends StatelessWidget {
  const _InstalledPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.45)),
      ),
      child: const Text(
        'Installed',
        style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
