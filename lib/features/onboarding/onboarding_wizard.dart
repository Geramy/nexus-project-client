// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_skipped_provider.dart';
import '../../core/providers/onboarding_controller.dart';
import '../../infrastructure/nexus/providers/nexus_account_providers.dart';
import '../../shared/ui/nexus_ui.dart';
import 'steps/account_step.dart';
import 'steps/done_step.dart';
import 'steps/local_server_step.dart';
import 'steps/project_step.dart';
import 'steps/welcome_step.dart';
import 'widgets/lemonade_credit.dart';

/// The linear first-run flow. Account → (optional local-server setup) → first
/// project → done. Signing in connects Nexus routed inference, so the local
/// server step is skipped; choosing "I'll run my own local servers" includes it.
enum OnboardingStep { welcome, account, localServer, project, done }

/// Full-screen first-run onboarding wizard. Owns step navigation + the
/// bring-your-own-server branch; the individual steps are presentational.
class OnboardingWizard extends ConsumerStatefulWidget {
  const OnboardingWizard({super.key});

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  OnboardingStep _step = OnboardingStep.welcome;

  /// Set when the user opts to run their own local servers instead of signing in
  /// — this is what inserts the local-server step into the sequence.
  bool _byoServers = false;

  /// The ordered steps for the current path (server step only on the BYO path).
  List<OnboardingStep> get _sequence => [
        OnboardingStep.welcome,
        OnboardingStep.account,
        if (_byoServers) OnboardingStep.localServer,
        OnboardingStep.project,
        OnboardingStep.done,
      ];

  void _go(OnboardingStep step) => setState(() => _step = step);

  void _next() {
    final seq = _sequence;
    final i = seq.indexOf(_step);
    if (i >= 0 && i < seq.length - 1) _go(seq[i + 1]);
  }

  void _back() {
    final seq = _sequence;
    final i = seq.indexOf(_step);
    if (i > 0) _go(seq[i - 1]);
  }

  /// Branch into the local LLM server setup step. Reachable whether or not the
  /// user is signed in (signed-in users may still add their own servers). When
  /// NOT signed in, record the auth skip so the login wall stays down later.
  void _goToServers() {
    if (!ref.read(nexusAuthProvider).isSignedIn) {
      ref.read(authSkippedNotifierProvider.notifier).skip();
    }
    setState(() => _byoServers = true);
    _go(OnboardingStep.localServer);
  }

  Future<void> _finish() async {
    await ref.read(onboardingControllerProvider.notifier).markComplete();
  }

  @override
  Widget build(BuildContext context) {
    final seq = _sequence;
    final index = seq.indexOf(_step);
    final canGoBack =
        _step != OnboardingStep.welcome && _step != OnboardingStep.done;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  _Header(stepCount: seq.length, currentIndex: index),
                  Gap.xl,
                  // Expanded gives the step a bounded region that fills the
                  // window; each step owns its own scrolling (the account step
                  // embeds AccountAuthForms, which brings its own scroll view —
                  // nesting two would throw an unbounded-height error). Using
                  // Spacers + Flexible here previously squeezed the step so its
                  // lower half fell below the fold.
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                      child: AnimatedSwitcher(
                        duration: AppMotion.base,
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _buildStep(),
                        ),
                      ),
                    ),
                  ),
                  Gap.lg,
                  if (canGoBack)
                    TextButton.icon(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back'),
                    ),
                  const LemonadeCredit(),
                  Gap.sm,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case OnboardingStep.welcome:
        return WelcomeStep(onStart: _next);
      case OnboardingStep.account:
        return AccountStep(
          onContinue: _next,
          onLocalServers: _goToServers,
        );
      case OnboardingStep.localServer:
        return LocalServerStep(onContinue: _next);
      case OnboardingStep.project:
        return ProjectStep(onCreated: _next);
      case OnboardingStep.done:
        return DoneStep(onFinish: _finish);
    }
  }
}

/// Brand mark + a row of progress dots reflecting position in the sequence.
class _Header extends StatelessWidget {
  const _Header({required this.stepCount, required this.currentIndex});

  final int stepCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
        Gap.sm,
        Text('Nexus Projects',
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Gap.md,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < stepCount; i++) ...[
              AnimatedContainer(
                duration: AppMotion.fast,
                width: i == currentIndex ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i <= currentIndex
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: AppRadius.smAll,
                ),
              ),
              if (i < stepCount - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}
