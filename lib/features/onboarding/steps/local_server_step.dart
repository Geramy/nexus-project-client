// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_shell_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/database/nexus_database.dart'
    show InferenceServersCompanion;
import '../../../infrastructure/inference/inference_backend_factory.dart'
    show backendForServer;
import '../../../infrastructure/lemonade/providers/lemonade_servers_provider.dart';
import '../../../infrastructure/lemonade/services/secure_key_store.dart';
import '../../../infrastructure/models/ui/inference_server.dart' as ui_server;
import '../../ai_providers/providers/ai_servers_cache_provider.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Step 3 (bring-your-own path only) — connect one or more local Lemonade
/// servers. Each add runs a real connection test (lists models) before saving,
/// then loops: "Add another" or "Continue".
class LocalServerStep extends ConsumerStatefulWidget {
  const LocalServerStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  ConsumerState<LocalServerStep> createState() => _LocalServerStepState();
}

class _LocalServerStepState extends ConsumerState<LocalServerStep> {
  final _name = TextEditingController(text: 'My Lemonade Server');
  final _url = TextEditingController(text: 'http://localhost:13305');
  final _apiKey = TextEditingController();

  bool _testing = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _testAndAdd() async {
    final name = _name.text.trim();
    final baseUrl = _url.text.trim();
    final apiKey = _apiKey.text.trim();
    if (name.isEmpty || baseUrl.isEmpty) {
      setState(() => _error = 'Name and URL are required.');
      return;
    }

    setState(() {
      _testing = true;
      _error = null;
      _success = null;
    });

    try {
      // Probe reachability BEFORE persisting, so we never save a dead server.
      final probe = ui_server.InferenceServer(
        id: 'probe',
        name: name,
        baseUrl: baseUrl,
        apiKey: apiKey,
        providerType: 'lemonade',
      );
      final models =
          await backendForServer(probe).listModels(showAll: true);

      final clientId = ref.read(currentClientIdProvider);
      final db = ref.read(nexusDatabaseProvider);
      await db.createInferenceServer(
        InferenceServersCompanion.insert(
          client_fk: clientId,
          name: name,
          baseUrl: baseUrl,
          apiKey: Value(apiKey),
          providerType: const Value('lemonade'),
          maxConcurrency: const Value(4),
          maxAgents: const Value(8),
          isEnabled: const Value(true),
          availableModelsJson: const Value('[]'),
          extraConfigJson: const Value('{}'),
          capabilitiesJson:
              const Value('{"isLemonade":true,"fullLemonadeManaged":true}'),
        ),
      );
      if (apiKey.isNotEmpty) {
        try {
          await SecureKeyStore.writeApiKey(name, apiKey);
        } catch (_) {}
      }
      ref.invalidate(lemonadeServersProvider);
      ref.read(aiServersCacheProvider.notifier).refresh();

      if (!mounted) return;
      setState(() {
        _success = 'Connected — ${models.length} model${models.length == 1 ? '' : 's'} available. Added "$name".';
        // Reset the form for the next server (add-another loop).
        _name.text = 'My Lemonade Server';
        _url.text = 'http://localhost:13305';
        _apiKey.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach that server: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clientId = ref.watch(currentClientIdProvider);
    final serversAsync = ref.watch(inferenceServersForClientProvider(clientId));
    final servers = serversAsync.valueOrNull ?? const [];

    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connect a local server',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        Gap.xs,
        Text(
          'Point Nexus at your own Lemonade server(s). We test the connection '
          'before saving.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: context.nx.textMuted),
        ),
        Gap.lg,
        if (servers.isNotEmpty) ...[
          for (final s in servers)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: NexusCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Icon(Icons.dns_outlined, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis),
                          Text(s.baseUrl,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: context.nx.textMuted),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Gap.sm,
        ],
        NexusCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a server', style: theme.textTheme.titleSmall),
              Gap.md,
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Server name', border: OutlineInputBorder()),
              ),
              Gap.sm,
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'Base URL', border: OutlineInputBorder()),
              ),
              Gap.sm,
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'API key (optional)', border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                Gap.sm,
                _Hint(_error!, color: theme.colorScheme.error, icon: Icons.error_outline),
              ],
              if (_success != null) ...[
                Gap.sm,
                _Hint(_success!, color: theme.colorScheme.primary, icon: Icons.check_circle_outline),
              ],
              Gap.md,
              OutlinedButton.icon(
                onPressed: _testing ? null : _testAndAdd,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_link, size: 18),
                label: Text(_testing ? 'Testing…' : 'Test & add server'),
              ),
            ],
          ),
        ),
        Gap.lg,
        GradientButton(
          onPressed: widget.onContinue,
          label: servers.isEmpty ? 'Skip for now' : 'Continue',
          icon: Icons.arrow_forward,
          expand: true,
        ),
        if (servers.isEmpty) ...[
          Gap.xs,
          Text('Optional — you can add servers later from AI Providers.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: context.nx.textMuted)),
        ],
      ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message, {required this.color, required this.icon});
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13))),
      ],
    );
  }
}
