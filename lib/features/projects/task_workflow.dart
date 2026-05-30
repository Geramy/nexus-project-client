// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

/// The kanban + execution state machine for orchestrated tasks.
///
/// Two orthogonal axes live on a task:
///  - [TaskStatus]: the kanban column the human sees (Todo → In Progress →
///    Review → Done, plus Blocked).
///  - [TaskExecStatus]: the orchestration phase (idle → queued → running →
///    submitted → verifying → passed/failed).
///
/// Events drive both. The transitions here are the single source of truth so
/// the DB helpers and any UI stay consistent.

/// Kanban column values (must match the Task Detail overview statuses).
class TaskStatus {
  static const todo = 'Todo';
  static const inProgress = 'In Progress';
  static const review = 'Review';
  static const done = 'Done';
  static const blocked = 'Blocked';
}

/// Orchestration execution phases stored in `tasks.executionStatus`.
///
/// The pipeline runs: idle → queued → running → submitted → verifying →
/// verified → (building → built, when the task requires a build gate) →
/// merging → done. A failed verify or build sends the task back to the board
/// (status Todo, exec `failed`) for the worker to re-engage.
class TaskExecStatus {
  static const idle = 'idle';
  static const queued = 'queued';
  static const running = 'running';
  static const submitted = 'submitted';
  static const verifying = 'verifying';

  /// Verification passed; awaiting the build gate (if required) or merge.
  static const verified = 'verified';

  /// Build/CI gate is running.
  static const building = 'building';

  /// Build/CI gate passed; awaiting merge.
  static const built = 'built';

  /// Coordinator is merging the task branch into main.
  static const merging = 'merging';

  /// Verify or build failed — task returned to the board for rework.
  static const failed = 'failed';

  /// Merged and integrated — fully complete.
  static const done = 'done';
}

/// Events that move a task through the loop.
enum TaskEvent {
  /// PM assigned the task and a worker session was spawned.
  startWork,

  /// Worker called submit_for_completion.
  submit,

  /// Verification Agent began running the proof.
  beginVerify,

  /// Verifier passed — task is verified and ready for the build gate (if any)
  /// or merge.
  verdictPass,

  /// Verifier failed — back to the board.
  verdictFail,

  /// The build/CI gate started running.
  beginBuild,

  /// The build/CI gate passed.
  buildPass,

  /// The build/CI gate failed — back to the board.
  buildFail,

  /// The Coordinator started merging the task branch.
  beginMerge,

  /// Coordinator merged the branch — task is fully done.
  approve,

  /// PM/Coordinator sent the task back to the board.
  reject,
}

/// The (status, execStatus) a task lands in after [event]. Pure — callers
/// persist the result. Returns the same pair for unknown combinations.
({String status, String exec}) applyEvent(TaskEvent event) {
  return switch (event) {
    TaskEvent.startWork => (status: TaskStatus.inProgress, exec: TaskExecStatus.running),
    TaskEvent.submit => (status: TaskStatus.review, exec: TaskExecStatus.submitted),
    TaskEvent.beginVerify => (status: TaskStatus.review, exec: TaskExecStatus.verifying),
    TaskEvent.verdictPass => (status: TaskStatus.review, exec: TaskExecStatus.verified),
    // Failure sends it back to the start of the board; the same agent re-engages.
    TaskEvent.verdictFail => (status: TaskStatus.todo, exec: TaskExecStatus.failed),
    TaskEvent.beginBuild => (status: TaskStatus.review, exec: TaskExecStatus.building),
    TaskEvent.buildPass => (status: TaskStatus.review, exec: TaskExecStatus.built),
    TaskEvent.buildFail => (status: TaskStatus.todo, exec: TaskExecStatus.failed),
    TaskEvent.beginMerge => (status: TaskStatus.review, exec: TaskExecStatus.merging),
    TaskEvent.approve => (status: TaskStatus.done, exec: TaskExecStatus.done),
    TaskEvent.reject => (status: TaskStatus.todo, exec: TaskExecStatus.idle),
  };
}
