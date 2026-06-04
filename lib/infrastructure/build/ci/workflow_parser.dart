// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:yaml/yaml.dart';

import 'workflow_model.dart';

/// Parses GitHub-Actions-format workflow YAML into a [WorkflowPlan].
///
/// Deliberately lenient: it tolerates missing or oddly-shaped fields and only
/// throws [WorkflowParseException] when the document is not recognizably a
/// workflow at all (no `jobs:` map).
class WorkflowParser {
  const WorkflowParser();

  /// Parse [yamlText] into a [WorkflowPlan]. [fileName] is used as the workflow
  /// name when the document has no top-level `name:`.
  WorkflowPlan parse(String yamlText, {String fileName = 'workflow.yml'}) {
    final dynamic doc;
    try {
      doc = loadYaml(yamlText);
    } catch (e) {
      throw WorkflowParseException('Invalid YAML in $fileName: $e');
    }

    final root = _toMap(doc);
    if (root == null) {
      throw WorkflowParseException(
        '$fileName is not a workflow document (expected a top-level map).',
      );
    }

    final jobsNode = _toMap(root['jobs']);
    if (jobsNode == null) {
      throw WorkflowParseException(
        '$fileName has no "jobs:" map — not a valid workflow.',
      );
    }

    final name = _str(root['name']) ?? fileName;

    final jobs = <WorkflowJob>[];
    jobsNode.forEach((key, value) {
      final jobId = key.toString();
      jobs.add(_parseJob(jobId, value));
    });

    return WorkflowPlan(name: name, jobs: jobs);
  }

  WorkflowJob _parseJob(String jobId, dynamic raw) {
    final job = _toMap(raw);
    if (job == null) {
      return WorkflowJob(id: jobId, name: jobId, steps: const []);
    }

    final name = _str(job['name']) ?? jobId;
    final runsOn = _runsOn(job['runs-on']);

    final steps = <WorkflowStep>[];
    final stepsNode = _toList(job['steps']);
    if (stepsNode != null) {
      for (final rawStep in stepsNode) {
        steps.add(_parseStep(rawStep));
      }
    }

    return WorkflowJob(id: jobId, name: name, runsOn: runsOn, steps: steps);
  }

  WorkflowStep _parseStep(dynamic raw) {
    final step = _toMap(raw);
    if (step == null) {
      return const WorkflowStep(name: 'step');
    }

    final run = _str(step['run']);
    final uses = _str(step['uses']);
    final shell = _str(step['shell']);
    final env = _strMap(step['env']);

    final name = _str(step['name']) ?? _defaultStepName(run, uses);

    return WorkflowStep(
      name: name,
      run: run,
      uses: uses,
      shell: shell,
      env: env,
    );
  }

  String _defaultStepName(String? run, String? uses) {
    if (run != null && run.trim().isNotEmpty) {
      final firstLine = run
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => run);
      return firstLine.trim();
    }
    if (uses != null && uses.trim().isNotEmpty) return uses.trim();
    return 'step';
  }

  /// `runs-on` may be a string, a list (take first), or a map/group (take
  /// `group` or first value). Returns null when it cannot be coerced.
  String? _runsOn(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    final list = _toList(raw);
    if (list != null) {
      for (final v in list) {
        final s = _str(v);
        if (s != null) return s;
      }
      return null;
    }
    final map = _toMap(raw);
    if (map != null) {
      final group = _str(map['group']);
      if (group != null) return group;
      for (final v in map.values) {
        final s = _str(v);
        if (s != null) return s;
      }
    }
    return _str(raw);
  }

  // --- coercion helpers -----------------------------------------------------

  Map<dynamic, dynamic>? _toMap(dynamic node) {
    if (node is YamlMap) return Map<dynamic, dynamic>.from(node);
    if (node is Map) return node;
    return null;
  }

  List<dynamic>? _toList(dynamic node) {
    if (node is YamlList) return List<dynamic>.from(node);
    if (node is List) return node;
    return null;
  }

  String? _str(dynamic node) {
    if (node == null) return null;
    if (node is String) return node;
    if (node is bool || node is num) return node.toString();
    return null;
  }

  Map<String, String> _strMap(dynamic node) {
    final map = _toMap(node);
    if (map == null) return const {};
    final out = <String, String>{};
    map.forEach((k, v) {
      final value = _str(v);
      if (value != null) out[k.toString()] = value;
    });
    return out;
  }
}
