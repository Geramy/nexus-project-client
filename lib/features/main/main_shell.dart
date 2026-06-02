// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/providers/lemonade_servers_provider.dart';
import 'package:nexus_projects_client/features/agents/persona_editor.dart';
import 'package:nexus_projects_client/features/main/widgets/left_sidebar.dart';
import 'package:nexus_projects_client/features/main/widgets/top_bar.dart';
import 'package:nexus_projects_client/features/main/widgets/resizable_divider.dart';
import 'package:nexus_projects_client/features/task_detail/task_detail_panel.dart';
import 'package:nexus_projects_client/features/tasks/tasks_view.dart';
import 'package:nexus_projects_client/features/projects/project_workspace_view.dart';
import 'package:nexus_projects_client/features/project_plans/plan_explorer.dart';
import 'package:nexus_projects_client/features/project_setup/setup_interview_panel.dart';
import 'package:nexus_projects_client/features/main/widgets/chat_sessions_sidebar.dart';
import 'package:nexus_projects_client/features/agents/agents_hub_view.dart';
import 'package:nexus_projects_client/features/agents/persona_bulk_select.dart';
import 'package:nexus_projects_client/features/agents/bulk_edit_personas_panel.dart';
import 'package:nexus_projects_client/features/ai_providers/ai_providers_page.dart';
import 'package:nexus_projects_client/features/ai_providers/providers/router_server_sync.dart';
import 'package:nexus_projects_client/features/ai_providers/widgets/admin_console/admin_console_widget.dart';
import 'package:nexus_projects_client/features/main/widgets/launch_center.dart';
import 'package:nexus_projects_client/features/main/widgets/activity_center.dart';
import 'package:nexus_projects_client/features/workspace/file_browser_view.dart';
import 'package:nexus_projects_client/features/workspace/code_and_git_right_panel.dart';
import 'package:nexus_projects_client/features/account/account_view.dart';
import 'package:nexus_projects_client/shared/ui/nexus_ui.dart';

/// Main 3-pane shell following the Nexus Projects UI Technical Spec
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  // Resizable pane widths (user requested percentages as defaults)
  bool _sizesInitialized = false;
  double _leftWidth = 240;
  double _rightWidth = 520;
  bool _rightCollapsed = false;
  final Map<MainView, bool> _collapsedByView = {};
  static const double _minPane = 160;

  /// Width of the collapsed left navigation rail (icon-only).
  static const double _leftRailWidth = 64;
  bool _leftExpanded = true;

  @override
  void initState() {
    super.initState();
    // Warm the current client's/project's page data up front so the first tab
    // switch shows cached data instead of a blank loading state.
    _warmClient(ref.read(currentClientIdProvider));
    _warmProject(ref.read(currentProjectIdProvider));
    // Load saved panel widths + collapsed state on startup.
    final layout = ref.read(panelLayoutNotifierProvider.notifier);
    layout.load();
    layout.loadCollapsed().then((saved) {
      if (!mounted) return;
      setState(() {
        _collapsedByView
          ..clear()
          ..addAll(saved);
        final current = ref.read(currentMainViewProvider);
        _rightCollapsed = _collapsedByView[current] ?? false;
      });
    });
  }

  void _updateLeftWidth(double delta) {
    setState(() {
      _leftWidth = (_leftWidth + delta).clamp(_minPane, 500);
    });
  }

  void _updateRightWidth(double delta) {
    setState(() {
      _rightWidth = (_rightWidth - delta).clamp(_minPane, double.infinity);
    });
  }

  /// Save the current right-panel width for the active view.
  void _savePanelWidth(MainView view) {
    ref.read(panelLayoutNotifierProvider.notifier).setWidth(view, _rightWidth);
  }

  /// Eagerly subscribe to the per-client page providers so their data is cached
  /// before the user opens those tabs (they're keepAlive, so this sticks).
  void _warmClient(int clientId) {
    ref.read(activityLogsForClientProvider(clientId));
    ref.read(agentPersonasForClientProvider(clientId));
    ref.read(inferenceServersForClientProvider(clientId));
    ref.read(deploymentsForClientProvider(clientId));
    ref.read(ciRunsForClientProvider(clientId));
  }

  /// Warm the per-project task list ahead of the Tasks tab.
  void _warmProject(int projectId) {
    ref.read(allTasksForProjectProvider(projectId));
  }

  @override
  Widget build(BuildContext context) {
    final currentView = ref.watch(currentMainViewProvider);
    final connectionMode = ref.watch(connectionModeNotifierProvider);

    // Keep the built-in Nexus Router (subscription) server reconciled with the
    // signed-in account for the whole session (materialize on login, remove on
    // logout). Result is intentionally ignored; we just keep the provider alive.
    ref.watch(routerServerSyncProvider);

    // Warm every page's data in the background as soon as the client/project is
    // known, so switching tabs shows cached data immediately instead of a blank
    // loading state. The providers are keepAlive, so a one-shot read keeps them
    // populated for the session.
    ref.listen<int>(currentClientIdProvider, (_, clientId) => _warmClient(clientId));
    ref.listen<int>(currentProjectIdProvider, (_, projectId) => _warmProject(projectId));

    // Surface a tappable notification whenever a task is approved (→ Done). The
    // DB broadcasts each completion; tapping "View" deep-links to that task.
    ref.listen(taskCompletedStreamProvider, (_, next) {
      final ev = next.valueOrNull;
      if (ev == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Task complete: "${ev.title}"'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              ref.read(currentProjectIdProvider.notifier).selectProject(ev.projectPk);
              ref.read(selectedTaskIdNotifierProvider.notifier).selectTask(ev.taskPk);
              ref.read(currentMainViewProvider.notifier).setView(MainView.tasks);
            },
          ),
        ));
    });

    // React to view changes via ref.listen — its callback runs AFTER the frame,
    // so we can safely modify providers + call setState (doing this inline in
    // build() throws "modified a provider while the widget tree was building").
    ref.listen<MainView>(currentMainViewProvider, (prev, next) {
      if (prev == null || prev == next) return;
      if (_sizesInitialized) {
        _savePanelWidth(prev); // persist the width we were showing for the old view
      }
      final savedWidth = ref.read(panelLayoutNotifierProvider.notifier).getWidth(next);
      setState(() {
        _rightWidth = savedWidth;
        _rightCollapsed = _collapsedByView[next] ?? false; // absent → expanded
      });
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          TopBar(connectionMode: connectionMode),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;

                // Initialize to user-requested percentages on first layout
                if (!_sizesInitialized) {
                  _leftWidth = totalWidth * 0.10;   // 10%
                  _rightWidth = totalWidth * 0.35;  // 35% (middle gets the remaining 55%)
                  _sizesInitialized = true;
                }

                // Re-clamp on window resize to keep reasonable proportions.
                // Reserve room for the rail (28) + divider (5) + a minimum middle
                // pane so left + right can never squeeze the Expanded middle
                // negative (which would overflow the Row to the right).
                const reserved = 28.0 + 5.0 + 200.0;
                _leftWidth = _leftWidth.clamp(_minPane, totalWidth * 0.35);
                final maxRight = (totalWidth - _leftWidth - reserved).clamp(_minPane, totalWidth);
                _rightWidth = _rightWidth.clamp(_minPane, maxRight);

                final leftPaneWidth = _leftExpanded ? _leftWidth : _leftRailWidth;

                return Row(
                  children: [
                    // LEFT PANE — slim icon rail or the full nav + Clients/
                    // Projects tree, toggled explicitly by the chevron button
                    // (no hover-driven expand/collapse).
                    AnimatedContainer(
                      duration: AppMotion.base,
                      curve: AppMotion.curve,
                      width: leftPaneWidth,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: _leftRailWidth,
                        maxWidth: _leftWidth,
                        child: SizedBox(
                          width: leftPaneWidth,
                          child: LeftSidebar(
                            collapsed: !_leftExpanded,
                            currentView: currentView,
                            onViewChanged: (view) {
                              ref.read(currentMainViewProvider.notifier).setView(view);
                            },
                            onToggleCollapsed: () => setState(() => _leftExpanded = !_leftExpanded),
                          ),
                        ),
                      ),
                    ),

                    // Draggable divider - Left <-> Center (only resizes the
                    // expanded width; hidden affordance while collapsed).
                    ResizableDivider(
                      onDrag: _updateLeftWidth,
                    ),

                    // CENTER / MIDDLE PANE — takes all remaining space, pinned
                    // top-left so content doesn't drift sideways on resize.
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _buildCenterContent(currentView, ref),
                      ),
                    ),

                    // Draggable divider - Center <-> Right (only when the panel is expanded)
                    if (!_rightCollapsed) ResizableDivider(onDrag: _updateRightWidth),

                    // Collapse / expand rail — always visible at the right edge.
                    _rightRail(currentView),

                    // RIGHT PANE — page-specific content, hidden when collapsed.
                    if (!_rightCollapsed)
                      SizedBox(
                        width: _rightWidth,
                        child: ClipRect(
                          child: _buildRightPanel(currentView, ref),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterContent(MainView view, WidgetRef ref) {
    final clientId = ref.watch(currentClientIdProvider);
    final projectId = ref.watch(currentProjectIdProvider);

    // Force rebuild when client or project changes so placeholder views update
    final key = ValueKey('$view-$clientId-$projectId');

    Widget child;
    switch (view) {
      case MainView.projectPlans:
        // Project workspace: Chat | Overview | Plan tabs. The plan
        // file-explorer lives in the right panel and opens plans into the
        // Plan tab.
        child = const ProjectWorkspaceView();
        break;
      case MainView.tasks:
        child = TasksView(
          onTaskSelected: (id) {
            ref.read(selectedTaskIdNotifierProvider.notifier).selectTask(id);
            ref.read(currentMainViewProvider.notifier).setView(MainView.tasks);
          },
        );
        break;
      case MainView.agents:
        child = const AgentsHubView();
        break;
      case MainView.aiProviders:
        child = const AiProvidersPage();
        break;
      case MainView.activity:
        child = const ActivityCenter();
        break;
      case MainView.launch:
        child = const LaunchCenter();
        break;
      case MainView.code:
        child = const FileBrowserView();
        break;
      case MainView.account:
        child = const AccountView();
        break;
    }

    return KeyedSubtree(key: key, child: child);
  }

  /// Builds the right panel content. Each [MainView] owns its own right panel —
  /// content never leaks across pages. Views without a dedicated detail panel
  /// show a contextual empty state instead of an unrelated panel.
  Widget _buildRightPanel(MainView currentView, WidgetRef ref) {
    switch (currentView) {
      case MainView.projectPlans:
        // The right outer panel follows the active workspace tab: Setup → the AI
        // interview chat, Plan → the plans file explorer, Chat (and other tabs) →
        // the chat-session history.
        switch (ref.watch(workspaceRightPanelProvider)) {
          case WorkspaceRightPanel.setupInterview:
            return SetupInterviewPanel(
              projectId: ref.watch(currentProjectIdProvider),
              clientId: ref.watch(currentClientIdProvider),
            );
          case WorkspaceRightPanel.planExplorer:
            return const PlanExplorer();
          case WorkspaceRightPanel.chatHistory:
            return const ChatSessionsSidebar();
        }

      case MainView.aiProviders:
        final selected = ref.watch(selectedLemonadeServerProvider);
        if (selected != null) {
          return AdminConsoleWidget(server: selected);
        }
        return _emptyRightPanel(
          Icons.dns_outlined,
          'No Provider Selected',
          'Select an AI Provider on the left to open its admin console.',
        );

      case MainView.agents:
        // While Personas select mode is active, the right outer panel hosts the
        // bulk editor (mirrors how Setup mode drives the projectPlans panel).
        if (ref.watch(personaBulkSelectionProvider).active) {
          return BulkEditPersonasPanel(clientId: ref.watch(currentClientIdProvider));
        }
        final editing = ref.watch(selectedPersonaNotifierProvider);
        if (editing != null) {
          return _buildRightPanelHeader(
            title: 'Edit Persona',
            subtitle: editing.name,
            onClose: () => ref.read(selectedPersonaNotifierProvider.notifier).clear(),
            // ValueKey forces a fresh editor State when the selected persona
            // changes, so fields/models never retain the previous persona's data.
            child: PersonaEditor(
              key: ValueKey(editing.id),
              personaName: editing.name,
              personaId: editing.id,
            ),
          );
        }
        return _emptyRightPanel(
          Icons.smart_toy_outlined,
          'No Persona Selected',
          'Select a persona from the list to view and edit its configuration.',
        );

      case MainView.tasks:
        final selectedTaskId = ref.watch(selectedTaskIdNotifierProvider);
        return TaskDetailPanel(taskId: selectedTaskId);

      case MainView.activity:
        return _emptyRightPanel(Icons.history, 'Activity', 'Select an event to see its details here.');
      case MainView.launch:
        return _emptyRightPanel(
          Icons.rocket_launch_outlined,
          'Launch',
          'Builds, packaging and live sites are shown in the main panel. Select a build to see its logs and status.',
        );
      case MainView.code:
        return const CodeAndGitRightPanel();
      case MainView.account:
        return _emptyRightPanel(
          Icons.account_circle_outlined,
          'Account',
          'Sign in to manage your subscription, usage and billing here.',
        );
    }
  }

  /// Minimal collapse/expand control: a single arrow at the bottom (no grey
  /// background). Toggling persists the choice for [view] across restarts.
  Widget _rightRail(MainView view) {
    return SizedBox(
      width: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            tooltip: _rightCollapsed ? 'Expand panel' : 'Collapse panel',
            iconSize: 18,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
            icon: Icon(_rightCollapsed ? Icons.chevron_left : Icons.chevron_right),
            onPressed: () {
              setState(() {
                _rightCollapsed = !_rightCollapsed;
                _collapsedByView[view] = _rightCollapsed;
              });
              ref.read(panelLayoutNotifierProvider.notifier).setCollapsed(view, _rightCollapsed);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Contextual empty state for views that have no detail to show yet.
  Widget _emptyRightPanel(IconData icon, String title, String subtitle) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      child: EmptyState(icon: icon, title: title, message: subtitle, compact: true),
    );
  }

  /// Shared right-panel header with title, subtitle and close button.
  Widget _buildRightPanelHeader({required String title, required String? subtitle, required VoidCallback onClose, required Widget child}) {
    final nx = context.nx;
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(bottom: BorderSide(color: nx.hairline)),
        ),
        child: Row(children: [
          Expanded(child: SectionHeader(title: title, subtitle: subtitle, dense: true)),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onClose),
        ]),
      ),
      Expanded(child: child),
    ]);
  }
}

// Organization refactor complete (2026-05):
// TopBar, ResizableDivider, BuildsCenter, DeploymentsCenter, ActivityCenter, and PlaceholderCenter
// have been extracted to dedicated files under features/main/widgets/.
// The old private implementations were removed from this shell coordinator file.
// All pages, tabs, and widgets for different concerns now live in their own .dart files.


