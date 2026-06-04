// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/update_provider.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Account-screen card for app updates: shows the installed version, an
/// "Automatic updates" toggle, a manual "Check for updates" action, and inline
/// status (checking / up to date / available / downloading / error). Sits in
/// [AccountView] alongside the appearance + lean-context settings.
class UpdateSettingsCard extends ConsumerWidget {
  const UpdateSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = ref.watch(updateControllerProvider);

    // Updates only apply to desktop builds; hide the card elsewhere.
    if (!c.supported) return const SizedBox.shrink();

    final version = c.currentVersion?.toString() ?? '—';
    final checking = c.phase == UpdatePhase.checking;
    final working =
        c.phase == UpdatePhase.downloading ||
        c.phase == UpdatePhase.verifying ||
        c.phase == UpdatePhase.launching;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: NexusCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('App updates', style: theme.textTheme.titleMedium),
                        Text(
                          'Nexus Projects v$version',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.nx.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (checking || working)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => ref
                          .read(updateControllerProvider)
                          .checkForUpdates(manual: true),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Check for updates'),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: c.autoCheck,
                onChanged: (v) =>
                    ref.read(updateControllerProvider).setAutoCheck(v),
                title: const Text('Automatic updates'),
                subtitle: Text(
                  'Check for a new version on launch and offer a one-click '
                  'install.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              _StatusLine(controller: c),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inline status row beneath the toggle — mirrors the controller phase.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;

    switch (c.phase) {
      case UpdatePhase.upToDate:
        return _line(
          theme,
          Icons.check_circle_outline,
          'You\'re on the latest version.',
          theme.colorScheme.primary,
        );
      case UpdatePhase.available:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: _line(
                  theme,
                  Icons.cloud_download_outlined,
                  'Update available: v${c.latest?.version}',
                  null,
                ),
              ),
              GradientButton(
                onPressed: () => c.startUpdate(),
                label: 'Update now',
                icon: Icons.download,
              ),
            ],
          ),
        );
      case UpdatePhase.downloading:
        final pct = c.progress;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pct != null
                    ? 'Downloading update… ${(pct * 100).toStringAsFixed(0)}%'
                    : 'Downloading update…',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: pct, minHeight: 4),
            ],
          ),
        );
      case UpdatePhase.verifying:
        return _line(
          theme,
          Icons.verified_outlined,
          'Verifying download…',
          theme.colorScheme.primary,
        );
      case UpdatePhase.launching:
        return _line(
          theme,
          Icons.rocket_launch_outlined,
          'Launching installer…',
          theme.colorScheme.primary,
        );
      case UpdatePhase.error:
        return _line(
          theme,
          Icons.error_outline,
          c.errorMessage ?? 'Update failed.',
          theme.colorScheme.error,
        );
      case UpdatePhase.idle:
      case UpdatePhase.checking:
        return const SizedBox.shrink();
    }
  }

  Widget _line(ThemeData theme, IconData icon, String text, Color? color) {
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }
}
