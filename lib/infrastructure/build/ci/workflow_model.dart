// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// Immutable, parsed representation of a GitHub-Actions-format workflow.
///
/// These plain value classes are produced by [WorkflowParser] and consumed by
/// [WorkflowRunner]; they intentionally model only the subset of the GitHub
/// Actions schema the local runner understands (jobs, steps, `run:`/`uses:`).
library;

/// A whole parsed workflow: a [name] plus its ordered [jobs].
class WorkflowPlan {
  final String name;
  final List<WorkflowJob> jobs;
  const WorkflowPlan({required this.name, required this.jobs});
}

/// A single job within a [WorkflowPlan].
class WorkflowJob {
  /// The job's key in the workflow's `jobs:` map.
  final String id;

  /// Display name (`name:` if present, otherwise [id]).
  final String name;

  /// The `runs-on` runner label, if any. Informational only — the local runner
  /// always executes on the host.
  final String? runsOn;

  /// The job's ordered steps.
  final List<WorkflowStep> steps;

  const WorkflowJob({
    required this.id,
    required this.name,
    this.runsOn,
    this.steps = const [],
  });
}

/// A single step within a [WorkflowJob].
class WorkflowStep {
  /// Display name. Defaults to the first line of [run], the [uses] value, or
  /// `'step'` when neither is present.
  final String name;

  /// The shell script to execute (`run:`). May be multiline. Null for actions.
  final String? run;

  /// An external action reference (`uses:`). Not supported locally — such steps
  /// are skipped by the runner.
  final String? uses;

  /// The requested shell (`shell:`), e.g. `bash` or `sh`. Null means default.
  final String? shell;

  /// Step-level environment variables (`env:`), values stringified.
  final Map<String, String> env;

  const WorkflowStep({
    required this.name,
    this.run,
    this.uses,
    this.shell,
    this.env = const {},
  });
}

/// Thrown when a YAML document is fundamentally not a parseable workflow
/// (e.g. it has no `jobs:` map).
class WorkflowParseException implements Exception {
  final String message;
  const WorkflowParseException(this.message);

  @override
  String toString() => 'WorkflowParseException: $message';
}
