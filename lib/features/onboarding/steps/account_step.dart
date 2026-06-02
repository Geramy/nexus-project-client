// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/widgets/account_auth_forms.dart';
import '../../../infrastructure/nexus/providers/nexus_account_providers.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Step 2 — the key step. Sign in or register to connect Nexus routed inference
/// (no server setup needed). When signed in you can continue, set up local
/// servers anyway, or log out and sign in / register again. When signed out you
/// can skip straight to local-server setup.
class AccountStep extends ConsumerWidget {
  const AccountStep({
    super.key,
    required this.onContinue,
    required this.onLocalServers,
  });

  /// Proceed with routed (signed-in) inference → project step.
  final VoidCallback onContinue;

  /// Branch to the local LLM server setup step.
  final VoidCallback onLocalServers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(nexusAuthProvider);
    final theme = Theme.of(context);

    if (auth.isSignedIn) {
      final who = auth.user?.email ?? auth.client?.name ?? 'your account';
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NexusCard(
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Signed in', style: theme.textTheme.titleMedium),
                        Text(
                          '$who · Nexus inference is ready — no server setup needed.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Gap.xl,
            GradientButton(
              onPressed: onContinue,
              label: 'Continue',
              icon: Icons.arrow_forward,
              expand: true,
            ),
            Gap.sm,
            OutlinedButton.icon(
              onPressed: onLocalServers,
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: const Text('Set up local LLM servers'),
            ),
            Gap.xs,
            TextButton.icon(
              onPressed: () => ref.read(nexusAuthProvider.notifier).logout(),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Log out'),
            ),
          ],
        ),
      );
    }

    // Signed-out: AccountAuthForms brings its own header + scroll view, so give
    // it bounded height via Expanded rather than nesting it in another scroll
    // view (which would throw an unbounded-height error). On success the auth
    // state flips and the signed-in branch renders.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: AccountAuthForms()),
        Gap.sm,
        Text(
          'Or run your own inference — skip sign-in and set up local LLM servers.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: context.nx.textMuted),
        ),
        TextButton(
          onPressed: onLocalServers,
          child: const Text('Skip — set up local LLM servers'),
        ),
      ],
    );
  }
}
