// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// The post-setup **Project Exploration** screen: a UML-style user-story tree in
/// the center and the discovery Coordinator chat on the right. The coordinator
/// proactively interviews the user and builds the story tree; NO tasks are
/// created until the user presses "Generate tasks from stories".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../coordinator_chat_screen.dart';
import 'exploration_session.dart';
import 'story_providers.dart';
import 'story_tree_canvas.dart';
import 'task_generator.dart';

/// The discovery system prompt, seeded from the project's setup profile.
final discoveryPromptProvider =
    FutureProvider.family<String, ({int projectId, String projectName})>((
      ref,
      key,
    ) {
      final db = ref.watch(nexusDatabaseProvider);
      return buildDiscoveryPrompt(db, key.projectId, key.projectName);
    });

class ProjectExplorationView extends ConsumerWidget {
  const ProjectExplorationView({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final int projectId;
  final String projectName;

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Walk the tree: each story → its own scoped AI session → 1..N tasks. The
    // run keeps us on this screen (explorationStatus stays 'active' until done)
    // and updates per-story progress; the canvas shows a bar on each story.
    await ref.read(taskGeneratorProvider(projectId)).run();
    final p = ref.read(taskGeneratorProvider(projectId)).progress;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Generated ${p.totalTasks} task${p.totalTasks == 1 ? '' : 's'} '
          'from ${p.totalStories} stor${p.totalStories == 1 ? 'y' : 'ies'}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stories = ref.watch(projectStoriesProvider(projectId)).valueOrNull ?? const [];
    final promptAsync = ref.watch(
      discoveryPromptProvider((projectId: projectId, projectName: projectName)),
    );
    final progress = ref.watch(taskGeneratorProvider(projectId)).progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header / action bar ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Icon(Icons.explore_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Explore "$projectName"',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Talk it through with the Coordinator — build out the user '
                      'stories, then generate tasks when the idea is solid.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (progress.running)
                // Stay on this screen while building; show overall progress.
                SizedBox(
                  width: 260,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Building tasks… ${progress.doneStories}/'
                        '${progress.totalStories} stories · '
                        '${progress.totalTasks} tasks',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress.totalStories == 0
                            ? null
                            : progress.fraction,
                        minHeight: 5,
                      ),
                    ],
                  ),
                )
              else ...[
                TextButton(
                  onPressed: () => _generate(context, ref),
                  child: const Text('Skip & generate'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: stories.isEmpty
                      ? null
                      : () => _generate(context, ref),
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: Text(
                    'Generate tasks from stories'
                    '${stories.isEmpty ? '' : ' (${stories.length})'}',
                  ),
                ),
              ],
            ],
          ),
        ),
        // ── Story tree (center) + discovery chat (right) ─────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: UserStoriesView(projectId: projectId)),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 460,
                child: promptAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Discovery error: $e')),
                  data: (prompt) => ProjectCoordinatorChatScreen(
                    key: ValueKey('discovery-chat-$projectId'),
                    projectId: projectId,
                    projectName: projectName,
                    discoveryMode: true,
                    systemPromptOverride: prompt,
                    autoOpenPrompt: kDiscoveryAutoOpen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
