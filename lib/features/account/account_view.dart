// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Account feature center panel. Two states:
///   - signed OUT → login + register forms (tabbed).
///   - signed IN  → dashboard: identity, usage meter, subscription, plan
///                  catalog (+ add-ons) with checkout, manage-billing, sign out.
///
/// An "Appearance" theme picker is shown above both states (this is the app's
/// settings-like surface). Matches the app's Material 3 / Card style.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/theme_provider.dart';
import '../../infrastructure/nexus/providers/nexus_account_providers.dart';
import '../../shared/ui/nexus_ui.dart';
import 'widgets/account_auth_forms.dart';
import 'widgets/account_dashboard.dart';

class AccountView extends ConsumerWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(nexusAuthProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AppearancePicker(),
          Expanded(
            child: auth.isSignedIn
                ? const AccountDashboard()
                // While hydrating the saved token from secure storage, show a
                // spinner instead of flashing the login form.
                : (auth.busy && auth.token == null)
                    ? const Center(child: CircularProgressIndicator())
                    : const AccountAuthForms(),
          ),
        ],
      ),
    );
  }
}

/// A compact theme picker (Appearance settings). Persists via [appThemeNotifierProvider].
class _AppearancePicker extends ConsumerWidget {
  const _AppearancePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(appThemeNotifierProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: NexusCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: LayoutBuilder(
              builder: (context, constraints) {
                final swatch = Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: AppRadius.mdAll,
                  ),
                );
                final labels = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Appearance',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(choice.description,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
                final dropdown = DropdownButton<AppThemeChoice>(
                  value: choice,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: (next) {
                    if (next != null) {
                      ref
                          .read(appThemeNotifierProvider.notifier)
                          .setChoice(next);
                    }
                  },
                  items: AppThemeChoice.values
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.label),
                          ))
                      .toList(),
                );

                // Narrow layout: stack vertically so nothing overflows.
                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          swatch,
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(child: labels),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      dropdown,
                    ],
                  );
                }

                return Row(
                  children: [
                    swatch,
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: labels),
                    const SizedBox(width: AppSpacing.lg),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: dropdown,
                    ),
                  ],
                );
              },
            ),
        ),
      ),
    );
  }
}
