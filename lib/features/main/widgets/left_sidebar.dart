// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart';
import 'package:nexus_projects_client/infrastructure/lemonade/providers/lemonade_servers_provider.dart';
import 'package:nexus_projects_client/features/agents/packs/agent_pack_catalog.dart';
import 'package:nexus_projects_client/features/onboarding/widgets/create_with_packs_dialog.dart';
import 'package:nexus_projects_client/shared/ui/nexus_ui.dart';

/// The eight primary navigation destinations, shared by the full sidebar and
/// the collapsed icon rail so the two never drift apart.
const List<(MainView, IconData, IconData?, String)> _navDestinations = [
  (MainView.projectPlans, Icons.space_dashboard_outlined, Icons.space_dashboard, 'Project Overview'),
  (MainView.tasks, Icons.fact_check_outlined, Icons.fact_check, 'Tasks'),
  (MainView.agents, Icons.smart_toy_outlined, Icons.smart_toy, 'Agents'),
  (MainView.aiProviders, Icons.dns_outlined, Icons.dns, 'AI Providers'),
  (MainView.code, Icons.code_rounded, null, 'Code & Git'),
  (MainView.launch, Icons.rocket_launch_outlined, Icons.rocket_launch, 'Launch'),
  (MainView.activity, Icons.history_rounded, null, 'Activity'),
  (MainView.account, Icons.account_circle_outlined, Icons.account_circle, 'Account'),
];

class LeftSidebar extends ConsumerWidget {
  final MainView currentView;
  final Function(MainView) onViewChanged;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  const LeftSidebar({
    super.key,
    required this.currentView,
    required this.onViewChanged,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collapsed) return _buildRail(context);

    final clientsAsync = ref.watch(allClientsProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scrollable region: clients, projects and navigation. Scrolls when
          // the pane is short instead of overflowing the Column.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          // Collapse control — explicit toggle (replaces hover expand/collapse).
          if (onToggleCollapsed != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: IconButton(
                  tooltip: 'Collapse sidebar',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onToggleCollapsed,
                ),
              ),
            ),
          const SizedBox(height: 4),

          // Clean Client + Projects hierarchy (B)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('CLIENTS'),
                const SizedBox(height: 4),

                clientsAsync.when(
                  data: (clients) {
                    final currentClientId = ref.watch(currentClientIdProvider);

                    return Column(
                      children: clients.map((client) {
                        final isSelected = client.client_pk == currentClientId;
                        return InkWell(
                          onTap: () {
                            ref.read(currentClientIdProvider.notifier).selectClient(client.client_pk);
                            Future.microtask(() async {
                              final db = ref.read(nexusDatabaseProvider);
                              final projs = await db.getProjectsForClient(client.client_pk);
                              if (projs.isNotEmpty) {
                                ref.read(currentProjectIdProvider.notifier).selectProject(projs.first.project_pk);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14) : null,
                              borderRadius: AppRadius.smAll,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    client.name + (client.isDefault ? ' (Default)' : ''),
                                    style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!client.isDefault)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deleteClient(context, ref, client),
                                    tooltip: 'Delete client',
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const SizedBox(height: 20),
                  error: (_, __) => const Text('Error'),
                ),

                TextButton.icon(
                  onPressed: () async {
                    final result = await showCreateWithPacksDialog(
                      context,
                      title: 'New Client',
                      nameLabel: 'Client name',
                      defaultName: 'New Client',
                    );
                    if (result != null) {
                      final db = ref.read(nexusDatabaseProvider);
                      final id = await db.createClientWithDefaults(
                        name: result.name,
                        packKeys: result.packKeys.toList(),
                      );
                      ref.read(currentClientIdProvider.notifier).selectClient(id);
                    }
                  },
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('New Client', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                ),

                const SizedBox(height: 8),
                const _SectionLabel('PROJECTS'),
                const SizedBox(height: 4),

                Consumer(
                  builder: (context, ref, _) {
                    final clientId = ref.watch(currentClientIdProvider);
                    final projsAsync = ref.watch(projectsForClientProvider(clientId));
                    final currProj = ref.watch(currentProjectIdProvider);

                    return projsAsync.when(
                      data: (projs) => Column(
                        children: projs.map((p) {
                          final sel = p.project_pk == currProj;
                          return InkWell(
                            onTap: () => ref.read(currentProjectIdProvider.notifier).selectProject(p.project_pk),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                              decoration: BoxDecoration(
                                color: sel ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
                                borderRadius: AppRadius.smAll,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(p.name, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _deleteProject(context, ref, p),
                                    tooltip: 'Delete project',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      loading: () => const SizedBox(),
                      error: (_, __) => const Text('Error'),
                    );
                  },
                ),

                TextButton.icon(
                  onPressed: () async {
                    final result = await showCreateWithPacksDialog(
                      context,
                      title: 'New Project',
                      nameLabel: 'Project name',
                      defaultName: 'New Project',
                    );
                    if (result != null) {
                      final db = ref.read(nexusDatabaseProvider);
                      final clientId = ref.read(currentClientIdProvider);
                      final id = await db.createProject(
                          ProjectsCompanion.insert(client_fk: clientId, name: result.name));
                      // Provision the chosen pack(s) into this project's client
                      // (dedupes against agents the client already has).
                      await db.provisionAgentPack(
                          clientId, agentsForPackKeys(result.packKeys));
                      ref.read(currentProjectIdProvider.notifier).selectProject(id);
                    }
                  },
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('New Project', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _SectionLabel('NAVIGATION'),
          ),
          const SizedBox(height: 8),

          for (final (view, icon, activeIcon, label) in _navDestinations)
            _NavItem(
              icon: icon,
              activeIcon: activeIcon,
              label: label,
              selected: currentView == view,
              onTap: () => onViewChanged(view),
            ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('LOCAL SERVER'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.circle, color: Colors.green, size: 10),
                    const Text('Running • localhost:7420', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsed icon-only rail shown when the mouse isn't over the sidebar.
  Widget _buildRail(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          if (onToggleCollapsed != null)
            IconButton(
              tooltip: 'Expand sidebar',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
              onPressed: onToggleCollapsed,
            ),
          const SizedBox(height: 8),
          for (final (view, icon, activeIcon, label) in _navDestinations)
            _NavItem(
              icon: icon,
              activeIcon: activeIcon,
              label: label,
              selected: currentView == view,
              onTap: () => onViewChanged(view),
              iconOnly: true,
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Tooltip(
              message: 'Local server running • localhost:7420',
              child: Icon(Icons.circle, color: Colors.green, size: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase section label used to group the sidebar tree.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: context.nx.textMuted,
      ),
    );
  }
}

/// VS Code activity-rail style navigation row: a left gradient indicator bar
/// marks the active destination, the icon swaps to its filled variant, and the
/// row gets a soft hover/active fill.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.activeIcon,
    this.iconOnly = false,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nx = context.nx;
    final accent = theme.colorScheme.primary;
    final selected = widget.selected;
    final Color? bg = selected
        ? accent.withValues(alpha: 0.14)
        : _hover
            ? nx.glass
            : null;
    final fg = selected
        ? accent
        : _hover
            ? theme.colorScheme.onSurface
            : nx.textMuted;
    final icon = selected ? (widget.activeIcon ?? widget.icon) : widget.icon;

    if (widget.iconOnly) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Tooltip(
            message: widget.label,
            waitDuration: const Duration(milliseconds: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.curve,
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: selected ? AppGradients.accent(theme.colorScheme) : null,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  Expanded(
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      curve: AppMotion.curve,
                      height: 40,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Icon(icon, size: 20, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
          child: Row(
            children: [
              // Left active-indicator bar — the signature activity-rail accent.
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  gradient: selected ? AppGradients.accent(theme.colorScheme) : null,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 19, color: fg),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected ? theme.colorScheme.onSurface : fg,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirm and delete a client + all its data.
Future<void> _deleteClient(BuildContext context, WidgetRef ref, Client client) async {
  if (client.isDefault) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cannot delete the default client.'), backgroundColor: Colors.orange),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Client'),
      content: Text('Delete "${client.name}" and ALL its projects, tasks, agents, and data? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ),
  );
  if (confirmed != true) return;

  final db = ref.read(nexusDatabaseProvider);
  final currentClientId = ref.read(currentClientIdProvider);
  await db.deleteClient(client.client_pk);

  // If the deleted client was the current one, switch to the default
  if (client.client_pk == currentClientId) {
    final defaultClient = await db.getDefaultClient();
    if (defaultClient != null) {
      ref.read(currentClientIdProvider.notifier).selectClient(defaultClient.client_pk);
      final projs = await db.getProjectsForClient(defaultClient.client_pk);
      if (projs.isNotEmpty) {
        ref.read(currentProjectIdProvider.notifier).selectProject(projs.first.project_pk);
      }
    }
  }
  // Invalidate the lemonade servers cache since servers were deleted
  ref.invalidate(lemonadeServersProvider);
}

/// Confirm and delete a project + all its tasks.
Future<void> _deleteProject(BuildContext context, WidgetRef ref, Project project) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Project'),
      content: Text('Delete "${project.name}" and ALL its tasks? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    ),
  );
  if (confirmed != true) return;

  final db = ref.read(nexusDatabaseProvider);
  final currentProjectId = ref.read(currentProjectIdProvider);
  await db.deleteProject(project.project_pk);

  // If the deleted project was the current one, switch to the first remaining
  if (project.project_pk == currentProjectId) {
    final clientId = ref.read(currentClientIdProvider);
    final projs = await db.getProjectsForClient(clientId);
    if (projs.isNotEmpty) {
      ref.read(currentProjectIdProvider.notifier).selectProject(projs.first.project_pk);
    }
  }
}