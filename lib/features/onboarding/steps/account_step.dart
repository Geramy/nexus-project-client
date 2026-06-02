// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/widgets/account_auth_forms.dart';
import '../../../infrastructure/nexus/providers/nexus_account_providers.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Step 2 — the key step. Sign in or register to connect Nexus routed inference
/// (no server setup needed). Already-signed-in users get a confirmation and
/// continue; the secondary action branches to bring-your-own local servers.
class AccountStep extends ConsumerWidget {
  const AccountStep({
    super.key,
    required this.onContinue,
    required this.onUseLocalServers,
  });

  final VoidCallback onContinue;
  final VoidCallback onUseLocalServers;

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
          ],
        ),
      );
    }

    // Signed-out: AccountAuthForms brings its own header + scroll view, so give
    // it bounded height via Expanded rather than nesting it in another scroll
    // view (which would throw an unbounded-height error). On success the auth
    // state flips and the branch above renders the Continue button.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: AccountAuthForms()),
        Gap.sm,
        Text(
          'No server setup required — sign in and Nexus handles inference.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: context.nx.textMuted),
        ),
        TextButton(
          onPressed: onUseLocalServers,
          child: const Text("I'll run my own local servers"),
        ),
      ],
    );
  }
}
