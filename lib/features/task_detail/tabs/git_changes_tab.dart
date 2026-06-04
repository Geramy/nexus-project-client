// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../infrastructure/workspace/git/git_engine_provider.dart';
import '../../../infrastructure/workspace/git/nxtprj_git_engine.dart';
import '../../../infrastructure/workspace/git_status.dart';
import '../../../infrastructure/workspace/workspace_provider.dart';
import '../../../shared/ui/nexus_ui.dart';

/// Git Changes tab: a read-only, real-time view of the project's git state
/// (current branch, recent commits, and working-tree changes). It re-fetches
/// whenever the workspace mutates via [workspaceRevisionProvider].
class GitChangesTab extends ConsumerWidget {
  final int taskId;
  final int projectId;
  final String? workBranch;

  const GitChangesTab({
    super.key,
    required this.taskId,
    required this.projectId,
    this.workBranch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineAsync = ref.watch(gitEngineProvider(projectId));
    // Watch the workspace revision so we re-fetch git data on every mutation.
    final rev = ref.watch(workspaceRevisionProvider(projectId));

    return engineAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(message: 'Failed to open git engine: $e'),
      data: (engine) =>
          _GitView(engine: engine, revision: rev, workBranch: workBranch),
    );
  }
}

/// All git data this tab needs, fetched in one shot so the UI renders from a
/// single consistent snapshot.
class _GitData {
  final GitStatusSnapshot status;
  final List<({String oid, String message, DateTime when, String author})>
  commits;
  const _GitData({required this.status, required this.commits});
}

class _GitView extends StatelessWidget {
  final NxtprjGitEngine engine;
  final int revision;
  final String? workBranch;

  const _GitView({
    required this.engine,
    required this.revision,
    required this.workBranch,
  });

  Future<_GitData> _load() async {
    final status = await engine.status();
    final commits = await engine.log(limit: 50);
    return _GitData(status: status, commits: commits);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GitData>(
      // The ValueKey embeds the workspace revision so the future re-runs
      // whenever the workspace mutates.
      key: ValueKey<int>(revision),
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorState(
            message: 'Failed to read git state: ${snap.error}',
          );
        }
        final data = snap.data;
        if (data == null) {
          return const _ErrorState(message: 'No git data available.');
        }
        return _GitContent(engine: engine, data: data, workBranch: workBranch);
      },
    );
  }
}

class _GitContent extends StatelessWidget {
  final NxtprjGitEngine engine;
  final _GitData data;
  final String? workBranch;

  const _GitContent({
    required this.engine,
    required this.data,
    required this.workBranch,
  });

  @override
  Widget build(BuildContext context) {
    final status = data.status;

    if (!status.hasRepo) {
      return const EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No git repository',
        message: 'No git repository in this workspace yet.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BranchHeader(status: status, workBranch: workBranch),
          Gap.lg,
          const SectionHeader(title: 'Commits', dense: true),
          Gap.sm,
          _CommitList(engine: engine, commits: data.commits),
          Gap.lg,
          const SectionHeader(title: 'Working Tree Changes', dense: true),
          Gap.sm,
          _WorkingTree(status: status),
        ],
      ),
    );
  }
}

class _BranchHeader extends StatelessWidget {
  final GitStatusSnapshot status;
  final String? workBranch;

  const _BranchHeader({required this.status, required this.workBranch});

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final branch = status.branch ?? '(detached)';
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.account_tree, size: 18),
            SizedBox(width: AppSpacing.sm),
            Text(
              'Current branch:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        StatusChip(branch, intent: ChipIntent.info, dense: true),
        if (workBranch != null && workBranch != status.branch) ...[
          const Text('Task branch:', style: TextStyle(fontSize: 12)),
          StatusChip(workBranch!, intent: ChipIntent.accent, dense: true),
        ],
        if (status.ahead > 0)
          Text(
            '${status.ahead} ahead',
            style: TextStyle(fontSize: 12, color: nx.success),
          ),
        if (status.behind > 0)
          Text(
            '${status.behind} behind',
            style: TextStyle(fontSize: 12, color: nx.warning),
          ),
      ],
    );
  }
}

class _CommitList extends StatelessWidget {
  final NxtprjGitEngine engine;
  final List<({String oid, String message, DateTime when, String author})>
  commits;

  const _CommitList({required this.engine, required this.commits});

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return const NexusCard(child: Text('No commits yet.'));
    }
    return NexusCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < commits.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _CommitTile(engine: engine, commit: commits[i]),
          ],
        ],
      ),
    );
  }
}

class _CommitTile extends StatefulWidget {
  final NxtprjGitEngine engine;
  final ({String oid, String message, DateTime when, String author}) commit;

  const _CommitTile({required this.engine, required this.commit});

  @override
  State<_CommitTile> createState() => _CommitTileState();
}

class _CommitTileState extends State<_CommitTile> {
  bool _expanded = false;
  Future<List<CommitFileChange>>? _diffFuture;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _diffFuture ??= widget.engine.commitDiff(widget.commit.oid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.commit;
    final shortOid = c.oid.length >= 7 ? c.oid.substring(0, 7) : c.oid;
    final firstLine = c.message.split('\n').first.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.commit, size: 18),
          title: Text(
            '$shortOid  $firstLine',
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${c.author.isEmpty ? 'unknown' : c.author} - ${_relativeTime(c.when)}',
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
          ),
          onTap: _toggle,
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 16, 8),
            child: FutureBuilder<List<CommitFileChange>>(
              future: _diffFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Text(
                    'Diff failed: ${snap.error}',
                    style: TextStyle(fontSize: 12, color: context.nx.danger),
                  );
                }
                final changes = snap.data ?? const <CommitFileChange>[];
                if (changes.isEmpty) {
                  return const Text(
                    'No file changes.',
                    style: TextStyle(fontSize: 12),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final ch in changes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          children: [
                            _ChangeBadge(kind: ch.change),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ch.path,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  final CommitChangeKind kind;
  const _ChangeBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    late final String letter;
    late final Color color;
    switch (kind) {
      case CommitChangeKind.added:
        letter = 'A';
        color = const Color(0xFF4FA66A);
        break;
      case CommitChangeKind.modified:
        letter = 'M';
        color = const Color(0xFFE2A03F);
        break;
      case CommitChangeKind.deleted:
        letter = 'D';
        color = const Color(0xFFD16969);
        break;
    }
    return _Badge(letter: letter, color: color);
  }
}

class _WorkingTree extends StatelessWidget {
  final GitStatusSnapshot status;
  const _WorkingTree({required this.status});

  @override
  Widget build(BuildContext context) {
    final dirty =
        status.byPath.entries.where((e) => gitStatusIsDirty(e.value)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    if (dirty.isEmpty) {
      return const NexusCard(child: Text('Working tree clean.'));
    }

    return NexusCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < dirty.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ChangedFileTile(path: dirty[i].key, status: dirty[i].value),
          ],
        ],
      ),
    );
  }
}

class _ChangedFileTile extends StatelessWidget {
  final String path;
  final GitFileStatus status;
  const _ChangedFileTile({required this.path, required this.status});

  @override
  Widget build(BuildContext context) {
    final deco = gitDecorationFor(status);
    return ListTile(
      dense: true,
      leading: deco == null
          ? const SizedBox(width: 22)
          : _Badge(letter: deco.badge, color: deco.color),
      title: Text(
        path,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          decoration: (deco?.strike ?? false)
              ? TextDecoration.lineThrough
              : TextDecoration.none,
          color: (deco?.muted ?? false) ? context.nx.textMuted : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        deco?.tooltip ?? status.name,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String letter;
  final Color color;
  const _Badge({required this.letter, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        letter.isEmpty ? '-' : letter,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final color = context.nx.danger;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: color),
            Gap.md,
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short relative timestamp like "3m ago", "2h ago", "5d ago", falling back
/// to an absolute date for older commits.
String _relativeTime(DateTime when) {
  final now = DateTime.now();
  final local = when.toLocal();
  final diff = now.difference(local);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
