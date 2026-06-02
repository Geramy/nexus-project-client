// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/nexus_ui.dart';
import 'providers/tag_providers.dart';
import 'setup_interview_panel.dart';
import 'setup_tab.dart';

/// Opens the project-setup experience as a full-screen, resumable WIZARD (the
/// same engine — interview + flow board — in a nicer shell). Reachable on new-
/// project creation and from the project Summary; resuming lands on the Overview
/// section. Saving is automatic (setup status + transcript persist), so closing
/// any time is safe.
Future<void> showProjectSetupWizard(
    BuildContext context, int projectId, int clientId) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          ProjectSetupWizard(projectId: projectId, clientId: clientId),
    ),
  );
}

enum _Section { overview, interview }

class ProjectSetupWizard extends ConsumerStatefulWidget {
  const ProjectSetupWizard(
      {super.key, required this.projectId, required this.clientId});

  final int projectId;
  final int clientId;

  @override
  ConsumerState<ProjectSetupWizard> createState() =>
      _ProjectSetupWizardState();
}

class _ProjectSetupWizardState extends ConsumerState<ProjectSetupWizard> {
  // Resuming always lands on the Overview section first.
  _Section _section = _Section.overview;

  @override
  Widget build(BuildContext context) {
    final status = ref
            .watch(projectRowProvider(widget.projectId))
            .valueOrNull
            ?.setupStatus ??
        'notStarted';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Save & close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Project setup'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Theme.of(context).dividerColor),
        ),
      ),
      body: switch (_section) {
        _Section.overview => _Overview(
            status: status,
            onContinue: () => setState(() => _section = _Section.interview),
          ),
        _Section.interview => _Interview(
            projectId: widget.projectId,
            clientId: widget.clientId,
            onBack: () => setState(() => _section = _Section.overview),
          ),
      },
    );
  }
}

/// Landing / resume section: explains setup, shows progress, and starts/continues.
class _Overview extends StatelessWidget {
  const _Overview({required this.status, required this.onContinue});
  final String status;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, action, hint) = switch (status) {
      'complete' => (
          'Setup complete',
          'Review & edit',
          'You can revisit your answers and adjust them any time.'
        ),
      'inProgress' || 'refining' => (
          'In progress',
          'Resume setup',
          'Pick up where you left off — your progress was saved.'
        ),
      'skipped' => (
          'Skipped',
          'Finish setup',
          'You skipped setup earlier — finish it whenever you like.'
        ),
      _ => (
          'Not started',
          'Start setup',
          'A short guided interview tailors the project to what you’re building.'
        ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: AppRadius.mdAll,
                ),
                child: const Icon(Icons.checklist_rtl,
                    color: Colors.white, size: 28),
              ),
              Gap.md,
              Text('Set up your project',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Gap.xs,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(label),
                  ),
                ],
              ),
              Gap.sm,
              Text(hint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: context.nx.textMuted)),
              Gap.xl,
              GradientButton(
                onPressed: onContinue,
                label: action,
                icon: Icons.arrow_forward,
                expand: true,
              ),
              Gap.sm,
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The interview section: the AI host chat beside the live profile/flow board —
/// the existing setup engine, reused inside the wizard.
class _Interview extends StatelessWidget {
  const _Interview({
    required this.projectId,
    required this.clientId,
    required this.onBack,
  });

  final int projectId;
  final int clientId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm, AppSpacing.xs, 0, 0),
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Overview'),
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 460,
                child: SetupInterviewPanel(
                    projectId: projectId, clientId: clientId),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: SetupTab(
                  key: ValueKey('wizard-setup-$projectId'),
                  projectId: projectId,
                  clientId: clientId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
