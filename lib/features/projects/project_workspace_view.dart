// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/features/projects/coordinator_chat_screen.dart';
import 'package:nexus_projects_client/features/projects/orchestration/project_orchestrator.dart';
import 'package:nexus_projects_client/features/projects/widgets/project_orchestration_controls.dart';
import 'package:nexus_projects_client/features/project_plans/plan_workspace.dart';
import 'package:nexus_projects_client/features/project_setup/providers/tag_providers.dart';
import 'package:nexus_projects_client/features/project_setup/setup_chat_controller.dart';
import 'package:nexus_projects_client/features/project_setup/setup_tab.dart';
import 'package:nexus_projects_client/features/project_setup/summary_tab.dart';

/// Center pane for a project: a tabbed workspace.
///   • Chat — the project Coordinator (first tab, the human's main surface).
///   • Overview — project settings: assigned agent, orchestration Start/Pause,
///     and the working-hours window.
///   • Plan — the plan currently opened from the Plans explorer (right panel).
///     Clicking a plan there auto-switches to this tab.
class ProjectWorkspaceView extends ConsumerStatefulWidget {
  const ProjectWorkspaceView({super.key});

  @override
  ConsumerState<ProjectWorkspaceView> createState() => _ProjectWorkspaceViewState();
}

class _ProjectWorkspaceViewState extends ConsumerState<ProjectWorkspaceView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  // Tab order is dynamic. While setup is unfinished it sits at index 1 so a
  // fresh project lands on it: Chat(0), Setup(1), Summary(2), Overview(3),
  // Plan(4). Once setup is complete it moves to the LAST slot and the rest
  // shift up: Chat(0), Summary(1), Overview(2), Plan(3), Setup(4). Kept in
  // sync by build() so the listeners below target the right tabs.
  int _setupTabIndex = 1;
  int _planTabIndex = 4;

  /// The project we've already auto-jumped to Setup for, so we don't fight the
  /// user when they navigate away — but DO re-gate when they switch to a
  /// different, not-yet-set-up project.
  int? _gatedProjectId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    // Publish whether Setup is the active tab so the MainShell right outer
    // panel can swap to the interview chat (instead of the Plan explorer).
    _tabs.addListener(_publishSetupMode);
    // Sync the initial value (a fresh mount starts on Chat → not setup) so a
    // stale flag from a prior mount can't leave the panel on the interview.
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishSetupMode());
  }

  void _publishSetupMode() {
    if (!mounted) return;
    final isSetup = _tabs.index == _setupTabIndex;
    if (ref.read(projectSetupModeProvider) != isSetup) {
      ref.read(projectSetupModeProvider.notifier).state = isSetup;
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_publishSetupMode);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = ref.watch(currentProjectIdProvider);
    final clientId = ref.watch(currentClientIdProvider);

    // Keep the autonomous worker-spawn loop alive while this project is open.
    // The driver itself only acts when orchestrationState == 'running'.
    ref.watch(projectOrchestratorProvider(projectId));

    // When a plan is opened from the explorer, surface the Plan tab.
    ref.listen<String?>(openPlanNotifierProvider, (prev, next) {
      if (next != null && next != prev && _tabs.index != _planTabIndex) {
        _tabs.animateTo(_planTabIndex);
      }
    });

    // When setup finishes (status flips to 'complete'), drop the user back on
    // the Chat tab — Setup has just slid to the last slot behind them.
    ref.listen(projectRowProvider(projectId), (prev, next) {
      final was = prev?.valueOrNull?.setupStatus;
      final now = next.valueOrNull?.setupStatus;
      if (was != 'complete' && now == 'complete') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tabs.animateTo(0);
        });
      }
    });

    final projsAsync = ref.watch(projectsForClientProvider(clientId));
    final projectName = projsAsync.maybeWhen(
      data: (projects) {
        for (final p in projects) {
          if (p.project_pk == projectId) return p.name;
        }
        return 'Project';
      },
      orElse: () => 'Project',
    );

    // Setup status drives gating (land a fresh project on Setup), tab order,
    // and the skip banner. Once 'complete', Setup slides to the last slot.
    final setupStatus =
        ref.watch(projectRowProvider(projectId)).valueOrNull?.setupStatus;
    final setupComplete = setupStatus == 'complete';
    _setupTabIndex = setupComplete ? 4 : 1;
    _planTabIndex = setupComplete ? 3 : 4;

    if (_gatedProjectId != projectId &&
        (setupStatus == 'notStarted' || setupStatus == 'inProgress')) {
      _gatedProjectId = projectId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabs.index != _setupTabIndex) {
          _tabs.animateTo(_setupTabIndex);
        }
      });
    }

    const chatTab = Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Chat');
    const setupTab =
        Tab(icon: Icon(Icons.checklist_rtl, size: 18), text: 'Setup');
    const summaryTab =
        Tab(icon: Icon(Icons.summarize_outlined, size: 18), text: 'Summary');
    const overviewTab = Tab(icon: Icon(Icons.tune, size: 18), text: 'Overview');
    const planTab =
        Tab(icon: Icon(Icons.description_outlined, size: 18), text: 'Plan');

    final setupView = SetupTab(
      key: ValueKey('project-setup-$projectId'),
      projectId: projectId,
      clientId: clientId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            chatTab,
            if (!setupComplete) setupTab,
            summaryTab,
            overviewTab,
            planTab,
            if (setupComplete) setupTab,
          ],
        ),
        const Divider(height: 1),
        if (setupStatus == 'skipped')
          _FinishSetupBanner(onFinish: () => _tabs.animateTo(_setupTabIndex)),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            // Chat + plan editors keep state; don't allow swipe so the code
            // editor / chat composer get the drag gestures instead.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ProjectCoordinatorChatScreen(
                key: ValueKey('project-chat-$projectId'),
                projectId: projectId,
                projectName: projectName,
              ),
              if (!setupComplete) setupView,
              SummaryTab(
                key: ValueKey('project-summary-$projectId'),
                projectId: projectId,
                clientId: clientId,
              ),
              _ProjectOverviewTab(projectId: projectId, clientId: clientId),
              const PlanWorkspaceView(),
              if (setupComplete) setupView,
            ],
          ),
        ),
      ],
    );
  }
}

/// Persistent nudge shown when the user skipped setup; setup stays reachable.
class _FinishSetupBanner extends StatelessWidget {
  const _FinishSetupBanner({required this.onFinish});
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 16, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Project setup was skipped. Finish it any time to generate plans.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
            TextButton(onPressed: onFinish, child: const Text('Finish setup')),
          ],
        ),
      ),
    );
  }
}

/// Overview / settings tab: assigned Coordinator agent, orchestration run
/// controls, and the working-hours window.
class _ProjectOverviewTab extends ConsumerWidget {
  final int projectId;
  final int clientId;
  const _ProjectOverviewTab({required this.projectId, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Orchestration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Start the autonomous loop to spawn worker agents for assigned tasks. '
          'Pause keeps state; Stop tears the loop down.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ProjectOrchestrationControls(projectId: projectId),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Working hours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ProjectWorkingHoursEditor(projectId: projectId),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Coordinator agent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _AgentDropdown(projectId: projectId, clientId: clientId),
          ),
        ),
      ],
    );
  }
}

/// Reactive dropdown to assign the project's Coordinator agent persona.
class _AgentDropdown extends ConsumerWidget {
  final int projectId;
  final int clientId;
  const _AgentDropdown({required this.projectId, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personasAsync = ref.watch(agentPersonasForClientProvider(clientId));
    final db = ref.watch(nexusDatabaseProvider);

    return personasAsync.when(
      data: (personas) {
        if (personas.isEmpty) {
          return const Text('No personas yet — create one in Agents.',
              style: TextStyle(fontSize: 12, color: Colors.grey));
        }
        return FutureBuilder<int?>(
          future: db.getOrAssignCoordinatorPersonaId(projectId),
          builder: (context, snap) {
            final raw = snap.data;
            final current = (raw != null && personas.where((p) => p.agent_pk == raw).length == 1) ? raw : null;
            return DropdownButtonFormField<int?>(
              initialValue: current,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Coordinator agent',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No agent (server default)')),
                for (final p in personas)
                  DropdownMenuItem(value: p.agent_pk, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) async {
                await db.setProjectAgentPersona(projectId, v);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Coordinator agent updated.'), duration: Duration(seconds: 2)),
                  );
                }
              },
            );
          },
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
