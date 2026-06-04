// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Tiny metrics sink shared by the live E2E tests so CI can collect timing as
/// MACHINE-READABLE data (for statistics later), not just log lines.
///
/// Each [record] is one timed event — a task completion, a Q&A turn, a phase.
/// On [flush] the events are written to two files in [dir] (default
/// `build/metrics`, overridable via the NEXUS_METRICS_DIR env var):
///   * `<name>.jsonl` — one JSON object per line (easy to append/aggregate);
///   * `<name>.csv`    — the same rows, for spreadsheets / quick plots.
/// The run is stamped with the CI commit + run id (GITHUB_SHA / GITHUB_RUN_ID)
/// so rows from many runs can be pooled and compared over time.
library;

import 'dart:convert';
import 'dart:io';

/// One timed measurement.
class Metric {
  Metric({
    required this.kind,
    required this.label,
    required this.ms,
    this.ok = true,
    this.extra = const {},
  });

  /// What was measured: e.g. 'task', 'qa_step', 'phase', 'run'.
  final String kind;

  /// Human label: the task title, the question text, the phase name.
  final String label;

  /// Duration in milliseconds.
  final int ms;

  /// Whether the measured thing succeeded (reached its terminal/expected state).
  final bool ok;

  /// Any extra structured fields (bytes produced, model, turn index, …).
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'label': label,
    'ms': ms,
    'ok': ok,
    ...extra,
  };
}

class MetricsLog {
  MetricsLog(this.name, {Map<String, String>? env})
    : _env = env ?? Platform.environment;

  /// Base filename (no extension), e.g. 'orchestrator_e2e'.
  final String name;
  final Map<String, String> _env;
  final List<Metric> _metrics = [];

  String get _runId =>
      _env['GITHUB_RUN_ID'] ?? _env['GITHUB_SHA'] ?? 'local';
  String get _sha => _env['GITHUB_SHA'] ?? 'local';

  void record(
    String kind,
    String label,
    Duration d, {
    bool ok = true,
    Map<String, Object?> extra = const {},
  }) {
    _metrics.add(
      Metric(
        kind: kind,
        label: label,
        ms: d.inMilliseconds,
        ok: ok,
        extra: extra,
      ),
    );
  }

  /// All recorded metrics (for asserting / printing a summary in the test).
  List<Metric> get metrics => List.unmodifiable(_metrics);

  /// A compact one-line-per-metric table for the CI log.
  String renderTable() {
    final b = StringBuffer()
      ..writeln()
      ..writeln('── Timing (run $_runId) ──');
    for (final m in _metrics) {
      final secs = (m.ms / 1000).toStringAsFixed(2);
      b.writeln(
        '   ${m.kind.padRight(8)} ${secs.padLeft(8)}s  '
        '${m.ok ? ' ' : '✗'} ${m.label}',
      );
    }
    return b.toString();
  }

  /// Write `<name>.jsonl` and `<name>.csv` under the metrics dir. Returns the
  /// directory written to.
  Future<Directory> flush() async {
    final dirPath = _env['NEXUS_METRICS_DIR'] ?? 'build/metrics';
    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    final stampedRows = _metrics
        .map((m) => {'run': _runId, 'sha': _sha, ...m.toJson()})
        .toList();

    final jsonl = stampedRows.map(jsonEncode).join('\n');
    await File('${dir.path}/$name.jsonl').writeAsString('$jsonl\n');

    // CSV with a stable column order; `extra` keys are unioned across rows.
    final baseCols = ['run', 'sha', 'kind', 'label', 'ms', 'ok'];
    final extraCols = <String>{
      for (final m in _metrics) ...m.extra.keys,
    }.toList()..sort();
    final cols = [...baseCols, ...extraCols];
    String cell(Object? v) {
      final s = (v ?? '').toString().replaceAll('"', '""');
      return '"$s"';
    }

    final csv = StringBuffer()..writeln(cols.join(','));
    for (final row in stampedRows) {
      csv.writeln(cols.map((c) => cell(row[c])).join(','));
    }
    await File('${dir.path}/$name.csv').writeAsString(csv.toString());
    return dir;
  }
}
