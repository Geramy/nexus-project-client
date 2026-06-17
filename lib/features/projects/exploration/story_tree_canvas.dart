// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// UML-style user-story tree: pan/zoom canvas of draggable story nodes with
/// parent→child edges, plus a side inspector to edit the selected story. Built
/// on the same primitives as the call-flow canvas (InteractiveViewer + a
/// CustomPaint edge layer + draggable Positioned cards). Reads the live
/// [projectStoriesProvider] and writes through the database directly.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../infrastructure/database/nexus_database.dart';
import '../../../shared/ui/design_tokens.dart';
import '../task_workflow.dart' show TaskStatus, TaskExecStatus;
import 'story_pdf_export.dart';
import 'story_providers.dart';
import 'task_generator.dart';

const double kStoryNodeWidth = 224;
const double kStoryNodeHeight = 92;

/// The canvas is sized dynamically to fit every node plus this much empty space
/// on the right/bottom, so a node never sits flush against an invisible wall —
/// there's always room to drag further, and the surface grows to keep an
/// off-to-the-side node reachable (a fixed box used to clip detailed trees).
const double _canvasBuffer = 700;

/// Floor so an empty/small tree still gets a comfortable working area.
const double _minCanvasW = 1600;
const double _minCanvasH = 1000;

/// Full User-Stories surface: the tree canvas + (when a node is selected) an
/// inspector. Used both as the persistent "User Stories" tab and inside the
/// post-setup Exploration screen.
class UserStoriesView extends ConsumerWidget {
  const UserStoriesView({super.key, required this.projectId});
  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedStoryProvider(projectId));
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: StoryTreeCanvas(projectId: projectId)),
              if (selected != null) ...[
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 340,
                  child: _StoryInspector(projectId: projectId, storyPk: selected),
                ),
              ],
            ],
          ),
        ),
        // Always-visible (scroll-independent) task rollup once stories have been
        // turned into tasks. Hidden until then.
        _TaskProgressBar(projectId: projectId),
      ],
    );
  }
}

/// A thin, static bar across the bottom of the User-Stories surface showing how
/// the project's tasks are progressing: green for done, orange for in-flight,
/// and an empty track for everything still to do. Reactive to the live task
/// stream; renders nothing until at least one task exists.
class _TaskProgressBar extends ConsumerWidget {
  const _TaskProgressBar({required this.projectId});
  final int projectId;

  /// Orchestration phases that mean a task is actively being worked.
  static const _activeExec = {
    TaskExecStatus.queued,
    TaskExecStatus.running,
    TaskExecStatus.submitted,
    TaskExecStatus.verifying,
    TaskExecStatus.verified,
    TaskExecStatus.building,
    TaskExecStatus.built,
    TaskExecStatus.merging,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(allTasksForProjectProvider(projectId)).value ??
        const <Task>[];
    if (tasks.isEmpty) return const SizedBox.shrink();

    var done = 0, working = 0, blocked = 0, todo = 0;
    for (final t in tasks) {
      if (t.status == TaskStatus.done ||
          t.executionStatus == TaskExecStatus.done) {
        done++;
      } else if (t.status == TaskStatus.blocked) {
        blocked++; // stuck / exhausted retries — surfaced in red
      } else if (t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.review ||
          _activeExec.contains(t.executionStatus)) {
        working++;
      } else {
        todo++; // Todo / idle — not started yet
      }
    }
    final total = tasks.length;
    final nx = context.nx;
    final scheme = Theme.of(context).colorScheme;
    // Theme-aware status colors (adapt to daylight / midnight / nebula):
    //   done → success (green), in progress → warning (orange),
    //   blocked → danger (red), not started → an empty track.
    final track = scheme.surfaceContainerHighest;

    return Material(
      color: scheme.surface,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Task progress',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    '$done done · $working in progress · $blocked blocked · '
                    '$todo to do  ·  $total total',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: nx.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              // The track is the empty "not started" remainder; coloured
              // segments fill from the left as tasks progress.
              child: Container(
                height: 12,
                color: track,
                child: Row(
                  // Stretch segments to the full 12px height — a childless
                  // ColoredBox is otherwise 0-tall and the bar reads as empty.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (done > 0)
                      Expanded(flex: done, child: ColoredBox(color: nx.success)),
                    if (working > 0)
                      Expanded(
                        flex: working,
                        child: ColoredBox(color: nx.warning),
                      ),
                    if (blocked > 0)
                      Expanded(
                        flex: blocked,
                        child: ColoredBox(color: nx.danger),
                      ),
                    // `todo` is the uncoloured remainder — the track shows through.
                    if (todo > 0) Expanded(flex: todo, child: const SizedBox()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoryTreeCanvas extends ConsumerStatefulWidget {
  const StoryTreeCanvas({super.key, required this.projectId});
  final int projectId;

  @override
  ConsumerState<StoryTreeCanvas> createState() => _StoryTreeCanvasState();
}

class _StoryTreeCanvasState extends ConsumerState<StoryTreeCanvas> {
  final _transform = TransformationController();
  int? _dragId;
  Offset? _dragPos;

  NexusDatabase get _db => ref.read(nexusDatabaseProvider);

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await exportStoryTreePdf(_db, widget.projectId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Exported $n stories to PDF.')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

  /// Deterministic top-down layered layout for nodes that don't have a saved
  /// position yet (parents centered over their children).
  Map<int, Offset> _autoLayout(List<UserStory> stories) {
    final childrenOf = <int?, List<UserStory>>{};
    for (final s in stories) {
      (childrenOf[s.parent_story_fk] ??= <UserStory>[]).add(s);
    }
    const stepX = kStoryNodeWidth + 40;
    const stepY = kStoryNodeHeight + 72;
    final pos = <int, Offset>{};
    var leaf = 0;

    double assign(UserStory s, int depth) {
      final kids = childrenOf[s.story_pk] ?? const <UserStory>[];
      double x;
      if (kids.isEmpty) {
        x = leaf * stepX;
        leaf++;
      } else {
        final xs = [for (final k in kids) assign(k, depth + 1)];
        x = (xs.first + xs.last) / 2;
      }
      pos[s.story_pk] = Offset(160 + x, 80 + depth * stepY);
      return x;
    }

    for (final root in childrenOf[null] ?? const <UserStory>[]) {
      assign(root, 0);
    }
    return pos;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(projectStoriesProvider(widget.projectId));
    final selected = ref.watch(selectedStoryProvider(widget.projectId));
    final genProgress = ref.watch(taskGeneratorProvider(widget.projectId)).progress;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Stories unavailable: $e')),
      data: (stories) {
        final auto = _autoLayout(stories);
        final byPk = {for (final s in stories) s.story_pk: s};

        Offset posOf(UserStory s) {
          if (_dragId == s.story_pk && _dragPos != null) return _dragPos!;
          if (s.posX != null && s.posY != null) {
            return Offset(s.posX!, s.posY!);
          }
          return auto[s.story_pk] ?? const Offset(160, 80);
        }

        // Size the canvas to fit every node (incl. one being dragged, since
        // posOf returns the live drag position) plus a buffer. Because this
        // recomputes on every drag frame, the wall stays ahead of the node — it
        // can never be pushed somewhere the user can't scroll to.
        var canvasW = _minCanvasW;
        var canvasH = _minCanvasH;
        for (final s in stories) {
          final p = posOf(s);
          if (p.dx + kStoryNodeWidth + _canvasBuffer > canvasW) {
            canvasW = p.dx + kStoryNodeWidth + _canvasBuffer;
          }
          if (p.dy + kStoryNodeHeight + _canvasBuffer > canvasH) {
            canvasH = p.dy + kStoryNodeHeight + _canvasBuffer;
          }
        }

        return Stack(
          children: [
            ColoredBox(
              color: scheme.surfaceContainerLowest,
              child: InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(800),
                minScale: 0.3,
                maxScale: 2.0,
                child: SizedBox(
                  width: canvasW,
                  height: canvasH,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _StoryEdgesPainter(
                            stories: stories,
                            byPk: byPk,
                            posOf: posOf,
                            color: scheme.outline,
                          ),
                        ),
                      ),
                      for (final s in stories)
                        Positioned(
                          left: posOf(s).dx,
                          top: posOf(s).dy,
                          child: _StoryNodeCard(
                            story: s,
                            selected: s.story_pk == selected,
                            gen: genProgress.byStory[s.story_pk],
                            onTap: () => ref
                                .read(
                                  selectedStoryProvider(
                                    widget.projectId,
                                  ).notifier,
                                )
                                .state = s.story_pk,
                            onPanStart: () => setState(() {
                              _dragId = s.story_pk;
                              _dragPos = posOf(s);
                            }),
                            onPanUpdate: (d) => setState(() {
                              // `d` is the gesture delta in the LOCAL space of the
                              // node card — which lives INSIDE the InteractiveViewer's
                              // scaled child, so it's already in canvas/scene units.
                              // Dividing by _scale again double-applied the zoom and
                              // sent the node ~1/scale too far when zoomed out (the
                              // "10x on a small screen" drift). Apply it 1:1.
                              _dragPos = (_dragPos ?? posOf(s)) + d;
                            }),
                            onPanEnd: () {
                              final p = _dragPos;
                              if (p != null) {
                                // Only floor at 0 (don't strand a node off the
                                // top-left). No upper wall — the canvas grows to
                                // fit, so a node dragged far out stays reachable.
                                _db.setUserStoryPosition(
                                  s.story_pk,
                                  p.dx.clamp(0.0, double.infinity),
                                  p.dy.clamp(0.0, double.infinity),
                                );
                              }
                              setState(() {
                                _dragId = null;
                                _dragPos = null;
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (stories.isEmpty)
              const Center(
                child: Text(
                  'No user stories yet.\nTalk to the Coordinator, or add one.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Positioned(
                right: 16,
                top: 16,
                child: Material(
                  color: scheme.surface,
                  elevation: 1,
                  borderRadius: BorderRadius.circular(8),
                  child: OutlinedButton.icon(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Export PDF'),
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'add-story-${widget.projectId}',
                onPressed: () async {
                  final id = await _db.createUserStory(
                    UserStoriesCompanion.insert(
                      project_fk: widget.projectId,
                      title: 'New story',
                      kind: const Value('story'),
                      orderIndex: Value(stories.length),
                    ),
                  );
                  ref
                      .read(selectedStoryProvider(widget.projectId).notifier)
                      .state = id;
                },
                icon: const Icon(Icons.add),
                label: const Text('Add story'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StoryNodeCard extends StatelessWidget {
  const _StoryNodeCard({
    required this.story,
    required this.selected,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.gen,
  });

  final UserStory story;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  /// Task-generation progress for this story (null = not generating).
  final StoryGen? gen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _statusColor(story.status, scheme);
    final isEpic = story.kind == 'epic';

    return GestureDetector(
      onTap: onTap,
      onPanStart: (_) => onPanStart(),
      onPanUpdate: (d) => onPanUpdate(d.delta),
      onPanEnd: (_) => onPanEnd(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: kStoryNodeWidth,
            height: kStoryNodeHeight,
            child: Material(
          elevation: selected ? 6 : 2,
          borderRadius: BorderRadius.circular(10),
          color: scheme.surface,
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isEpic
                                ? Icons.folder_special_outlined
                                : Icons.turned_in_not_outlined,
                            size: 14,
                            color: accent,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              story.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        story.narrative.isEmpty
                            ? '${_kindLabel(story.kind)} · ${story.status}'
                            : story.narrative,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
          ),
          if (gen != null)
            Positioned(
              right: 4,
              bottom: 2,
              child: _genBadge(context, gen!),
            ),
        ],
      ),
    );
  }
}

/// Small per-story task-generation progress badge on a node.
Widget _genBadge(BuildContext context, StoryGen gen) {
  final scheme = Theme.of(context).colorScheme;
  Widget chip(Color bg, Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: child,
  );
  return switch (gen.status) {
    StoryGenStatus.pending => chip(
      scheme.surfaceContainerHighest,
      Text('queued', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
    ),
    StoryGenStatus.generating => chip(
      scheme.primaryContainer,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 5),
          Text('building…', style: TextStyle(fontSize: 9)),
        ],
      ),
    ),
    StoryGenStatus.done => chip(
      const Color(0xFF2E9E5B),
      Text(
        '✓ ${gen.tasks} task${gen.tasks == 1 ? '' : 's'}',
        style: const TextStyle(fontSize: 9, color: Colors.white),
      ),
    ),
    StoryGenStatus.error => chip(
      scheme.errorContainer,
      Text('failed', style: TextStyle(fontSize: 9, color: scheme.onErrorContainer)),
    ),
  };
}

class _StoryInspector extends ConsumerStatefulWidget {
  const _StoryInspector({required this.projectId, required this.storyPk});
  final int projectId;
  final int storyPk;

  @override
  ConsumerState<_StoryInspector> createState() => _StoryInspectorState();
}

class _StoryInspectorState extends ConsumerState<_StoryInspector> {
  final _title = TextEditingController();
  final _narrative = TextEditingController();
  final _criteria = TextEditingController();
  int? _loadedFor;

  NexusDatabase get _db => ref.read(nexusDatabaseProvider);

  @override
  void dispose() {
    _title.dispose();
    _narrative.dispose();
    _criteria.dispose();
    super.dispose();
  }

  void _hydrate(UserStory s) {
    if (_loadedFor == s.story_pk) return;
    _loadedFor = s.story_pk;
    _title.text = s.title;
    _narrative.text = s.narrative;
    _criteria.text = s.acceptanceCriteria ?? '';
  }

  /// Stories that may legally become [story]'s parent: all except itself and its
  /// own descendants (nesting under your own subtree would create a cycle).
  List<UserStory> _parentCandidates(List<UserStory> all, UserStory story) {
    final banned = <int>{story.story_pk};
    var changed = true;
    while (changed) {
      changed = false;
      for (final s in all) {
        final p = s.parent_story_fk;
        if (p != null && banned.contains(p) && !banned.contains(s.story_pk)) {
          banned.add(s.story_pk);
          changed = true;
        }
      }
    }
    return all.where((s) => !banned.contains(s.story_pk)).toList();
  }

  Future<void> _save() async {
    await _db.updateUserStory(
      widget.storyPk,
      UserStoriesCompanion(
        title: Value(_title.text.trim().isEmpty ? 'Untitled' : _title.text.trim()),
        narrative: Value(_narrative.text.trim()),
        acceptanceCriteria: Value(
          _criteria.text.trim().isEmpty ? null : _criteria.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(projectStoriesProvider(widget.projectId));
    final story = async.value
        ?.where((s) => s.story_pk == widget.storyPk)
        .firstOrNull;
    if (story == null) return const SizedBox.shrink();
    _hydrate(story);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text(
                'Story',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref
                    .read(selectedStoryProvider(widget.projectId).notifier)
                    .state = null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: story.kind,
            decoration: const InputDecoration(
              labelText: 'Kind',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'epic', child: Text('Epic')),
              DropdownMenuItem(value: 'story', child: Text('Story')),
              DropdownMenuItem(value: 'substory', child: Text('Sub-story')),
            ],
            onChanged: (v) => _db.updateUserStory(
              widget.storyPk,
              UserStoriesCompanion(kind: Value(v ?? 'story')),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: story.status,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'draft', child: Text('Draft')),
              DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
              DropdownMenuItem(value: 'done', child: Text('Done')),
            ],
            onChanged: (v) => _db.updateUserStory(
              widget.storyPk,
              UserStoriesCompanion(status: Value(v ?? 'draft')),
            ),
          ),
          const SizedBox(height: 10),
          // Re-parent: nest this story under another (or make it a root). Excludes
          // itself and its own descendants so you can't create a cycle.
          DropdownButtonFormField<int?>(
            initialValue: story.parent_story_fk,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Parent (nest under)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('— None (root) —'),
              ),
              for (final s in _parentCandidates(
                async.value ?? const [],
                story,
              ))
                DropdownMenuItem<int?>(
                  value: s.story_pk,
                  child: Text(
                    '#${s.story_pk}  ${s.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => _db.updateUserStory(
              widget.storyPk,
              UserStoriesCompanion(parent_story_fk: Value(v)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _narrative,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'As a … I want … so that …',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _criteria,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Acceptance criteria',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.subdirectory_arrow_right, size: 16),
                label: const Text('Add sub-story'),
                onPressed: () async {
                  final id = await _db.createUserStory(
                    UserStoriesCompanion.insert(
                      project_fk: widget.projectId,
                      parent_story_fk: Value(widget.storyPk),
                      title: 'New sub-story',
                      kind: const Value('substory'),
                    ),
                  );
                  ref
                      .read(selectedStoryProvider(widget.projectId).notifier)
                      .state = id;
                },
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
                onPressed: () async {
                  await _db.deleteUserStory(widget.storyPk);
                  ref
                      .read(selectedStoryProvider(widget.projectId).notifier)
                      .state = null;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _NotesSection(storyPk: widget.storyPk),
          const SizedBox(height: 16),
          _LinkedTasks(storyPk: widget.storyPk),
        ],
      ),
    );
  }
}

/// Descriptive notes on a story, shown as clickable pills; tap to view/edit.
class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.storyPk});
  final int storyPk;

  String _pill(String body) {
    final one = body.replaceAll('\n', ' ').trim();
    return one.length > 26 ? '${one.substring(0, 26)}…' : one;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    final notes = ref.watch(storyNotesProvider(storyPk)).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Notes',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add note', style: TextStyle(fontSize: 12)),
              onPressed: () => _editNote(context, db, storyPk, null),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (notes.isEmpty)
          Text(
            'No notes yet.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in notes)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.sticky_note_2_outlined, size: 14),
                  label: Text(_pill(n.body)),
                  onPressed: () => _viewNote(context, db, n),
                ),
            ],
          ),
      ],
    );
  }
}

/// View a note full-size with Edit / Delete.
Future<void> _viewNote(
  BuildContext context,
  NexusDatabase db,
  StoryNote note,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Note'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(child: Text(note.body)),
      ),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Delete'),
          onPressed: () async {
            await db.deleteStoryNote(note.note_pk);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
          onPressed: () {
            Navigator.pop(ctx);
            _editNote(context, db, note.story_fk, note);
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Add a new note (note == null) or edit an existing one.
Future<void> _editNote(
  BuildContext context,
  NexusDatabase db,
  int storyPk,
  StoryNote? note,
) async {
  final ctrl = TextEditingController(text: note?.body ?? '');
  final body = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(note == null ? 'Add note' : 'Edit note'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'A detail, decision, constraint, or open question…',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (body == null || body.isEmpty) return;
  if (note == null) {
    await db.createStoryNote(storyPk, body);
  } else {
    await db.updateStoryNote(note.note_pk, body);
  }
}

/// Shows the tasks generated from this story (story → task(s) backlink).
class _LinkedTasks extends ConsumerWidget {
  const _LinkedTasks({required this.storyPk});
  final int storyPk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(nexusDatabaseProvider);
    return FutureBuilder(
      future: db.getTasksForStory(storyPk),
      builder: (context, snap) {
        final tasks = snap.data ?? const [];
        if (tasks.isEmpty) {
          return Text(
            'No linked tasks yet — generated when you build tasks from stories.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Linked tasks (${tasks.length})',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final t in tasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.task_alt, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StoryEdgesPainter extends CustomPainter {
  _StoryEdgesPainter({
    required this.stories,
    required this.byPk,
    required this.posOf,
    required this.color,
  });

  final List<UserStory> stories;
  final Map<int, UserStory> byPk;
  final Offset Function(UserStory) posOf;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;

    for (final s in stories) {
      final parentPk = s.parent_story_fk;
      if (parentPk == null) continue;
      final parent = byPk[parentPk];
      if (parent == null) continue;
      final pp = posOf(parent);
      final cp = posOf(s);
      final start = Offset(pp.dx + kStoryNodeWidth / 2, pp.dy + kStoryNodeHeight);
      final end = Offset(cp.dx + kStoryNodeWidth / 2, cp.dy);
      final dy = (end.dy - start.dy).abs().clamp(40, 240) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx, start.dy + dy, end.dx, end.dy - dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
      canvas.drawCircle(end, 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _StoryEdgesPainter old) => true;
}

Color _statusColor(String status, ColorScheme scheme) => switch (status) {
  'confirmed' => scheme.primary,
  'done' => const Color(0xFF2E9E5B),
  _ => scheme.outline, // draft
};

String _kindLabel(String kind) => switch (kind) {
  'epic' => 'Epic',
  'substory' => 'Sub-story',
  _ => 'Story',
};
