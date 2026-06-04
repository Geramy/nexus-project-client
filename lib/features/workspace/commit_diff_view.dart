// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';

import 'code_highlight.dart';

/// Open a side-by-side before/after diff for one file in a commit.
/// [before] is the parent commit's content (null = file was added),
/// [after] is this commit's content (null = file was deleted).
Future<void> showCommitFileDiff(
  BuildContext context, {
  required String path,
  required String? before,
  required String? after,
}) {
  ensureHighlightLanguages();
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 1100,
        height: 720,
        child: _CommitDiffBody(path: path, before: before, after: after),
      ),
    ),
  );
}

enum _Kind { equal, added, removed, modified }

/// One side-by-side row: a left (old) cell and/or a right (new) cell.
class _Row {
  final String? left;
  final int? leftNo;
  final String? right;
  final int? rightNo;
  final _Kind kind;
  const _Row({
    this.left,
    this.leftNo,
    this.right,
    this.rightNo,
    required this.kind,
  });
}

class _CommitDiffBody extends StatelessWidget {
  final String path;
  final String? before;
  final String? after;
  const _CommitDiffBody({
    required this.path,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final theme = highlightThemeFor(brightness);
    final bg = highlightBackground(brightness);
    final langId = languageIdForPath(path);
    final rows = _buildRows(before, after);

    final added = rows
        .where((r) => r.kind == _Kind.added || r.kind == _Kind.modified)
        .length;
    final removed = rows
        .where((r) => r.kind == _Kind.removed || r.kind == _Kind.modified)
        .length;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.difference_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (removed > 0)
                Text(
                  '−$removed  ',
                  style: const TextStyle(
                    color: Color(0xFFD16969),
                    fontSize: 12,
                  ),
                ),
              if (added > 0)
                Text(
                  '+$added',
                  style: const TextStyle(
                    color: Color(0xFF4FA66A),
                    fontSize: 12,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Column titles
        Row(
          children: const [
            Expanded(child: _ColTitle('Before')),
            SizedBox(width: 1),
            Expanded(child: _ColTitle('After')),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: bg,
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      '(no content)',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) =>
                        _DiffRow(row: rows[i], langId: langId, theme: theme),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ColTitle extends StatelessWidget {
  final String text;
  const _ColTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    ),
  );
}

class _DiffRow extends StatelessWidget {
  final _Row row;
  final String? langId;
  final Map<String, TextStyle> theme;
  const _DiffRow({
    required this.row,
    required this.langId,
    required this.theme,
  });

  static const _addBg = Color(0x334FA66A);
  static const _delBg = Color(0x33D16969);

  @override
  Widget build(BuildContext context) {
    final leftBg = (row.kind == _Kind.removed || row.kind == _Kind.modified)
        ? _delBg
        : null;
    final rightBg = (row.kind == _Kind.added || row.kind == _Kind.modified)
        ? _addBg
        : null;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _cell(context, row.leftNo, row.left, leftBg)),
          const VerticalDivider(width: 1),
          Expanded(child: _cell(context, row.rightNo, row.right, rightBg)),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int? lineNo, String? text, Color? bg) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              lineNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _code(text)),
        ],
      ),
    );
  }

  Widget _code(String? text) {
    if (text == null) return const SizedBox.shrink();
    if (text.isEmpty) return const SizedBox(height: 16);
    if (langId == null) {
      return Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.3,
        ),
      );
    }
    return HighlightView(
      text,
      language: langId!,
      theme: theme,
      padding: EdgeInsets.zero,
      textStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.5,
        height: 1.3,
      ),
    );
  }
}

/// Build aligned side-by-side rows from before/after text via an LCS line diff.
List<_Row> _buildRows(String? before, String? after) {
  final a = (before ?? '').isEmpty && before == null
      ? <String>[]
      : _lines(before);
  final b = (after ?? '').isEmpty && after == null ? <String>[] : _lines(after);

  // Guard against pathological cost on huge files: above the cap, don't run the
  // O(n*m) LCS — show everything as removed then added.
  const cap = 4000;
  final ops = (a.length > cap || b.length > cap) ? _bulk(a, b) : _lcs(a, b);

  final rows = <_Row>[];
  var ai = 0, bi = 0; // running line numbers (1-based on emit)
  var k = 0;
  while (k < ops.length) {
    final op = ops[k];
    if (op.equal) {
      rows.add(
        _Row(
          left: op.text,
          leftNo: ++ai,
          right: op.text,
          rightNo: ++bi,
          kind: _Kind.equal,
        ),
      );
      k++;
      continue;
    }
    // Gather a contiguous change block (removes + adds).
    final removes = <String>[];
    final adds = <String>[];
    while (k < ops.length && !ops[k].equal) {
      if (ops[k].removed) {
        removes.add(ops[k].text);
      } else {
        adds.add(ops[k].text);
      }
      k++;
    }
    final n = math.max(removes.length, adds.length);
    for (var i = 0; i < n; i++) {
      final l = i < removes.length ? removes[i] : null;
      final r = i < adds.length ? adds[i] : null;
      final kind = (l != null && r != null)
          ? _Kind.modified
          : (l != null ? _Kind.removed : _Kind.added);
      rows.add(
        _Row(
          left: l,
          leftNo: l != null ? ++ai : null,
          right: r,
          rightNo: r != null ? ++bi : null,
          kind: kind,
        ),
      );
    }
  }
  return rows;
}

List<String> _lines(String? s) {
  if (s == null || s.isEmpty) return <String>[];
  final out = s.split('\n');
  // A trailing newline yields a spurious empty last element — drop it.
  if (out.isNotEmpty && out.last.isEmpty) out.removeLast();
  return out;
}

class _Op {
  final String text;
  final bool equal;
  final bool removed; // meaningful only when !equal
  const _Op(this.text, {required this.equal, required this.removed});
}

List<_Op> _bulk(List<String> a, List<String> b) => [
  for (final l in a) _Op(l, equal: false, removed: true),
  for (final l in b) _Op(l, equal: false, removed: false),
];

/// Classic LCS line diff → ordered ops (equal / removed / added).
List<_Op> _lcs(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final dp = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  final ops = <_Op>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      ops.add(_Op(a[i], equal: true, removed: false));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      ops.add(_Op(a[i], equal: false, removed: true));
      i++;
    } else {
      ops.add(_Op(b[j], equal: false, removed: false));
      j++;
    }
  }
  while (i < n) {
    ops.add(_Op(a[i++], equal: false, removed: true));
  }
  while (j < m) {
    ops.add(_Op(b[j++], equal: false, removed: false));
  }
  return ops;
}
