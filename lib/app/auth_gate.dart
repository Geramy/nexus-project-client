// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/auth_skipped_provider.dart';
import 'package:nexus_projects_client/features/account/widgets/account_auth_forms.dart';
import 'package:nexus_projects_client/features/main/main_shell.dart';
import 'package:nexus_projects_client/infrastructure/nexus/providers/nexus_account_providers.dart';
import 'package:nexus_projects_client/shared/ui/nexus_ui.dart';

/// Top-level auth gate. Routes unauthenticated users to a full-screen
/// login/register page and signed-in users to the main workspace. While the
/// saved token is read back from secure storage, shows a splash so the login
/// form never flashes before a returning user is recognized. Users can also
/// "Skip for now" to explore the app before signing in.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(nexusAuthProvider);

    if (auth.busy && auth.token == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isSignedIn && !ref.watch(authSkippedProvider)) {
      return const _LoginScreen();
    }
    return const MainShell();
  }
}

class _LoginScreen extends ConsumerWidget {
  const _LoginScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: const Icon(Icons.hub, color: Colors.white, size: 30),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Nexus Projects',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Sign in to your workspace',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: context.nx.textMuted),
                ),
                AccountAuthForms(
                  onSkip: () =>
                      ref.read(authSkippedProvider.notifier).skip(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
