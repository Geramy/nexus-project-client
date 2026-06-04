// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';

void main() {
  group('task status machine', () {
    test('pickup (enqueue) stays on the board — NOT In Progress', () {
      final r = applyEvent(TaskEvent.enqueue);
      expect(r.status, TaskStatus.todo);
      expect(r.exec, TaskExecStatus.queued);
    });

    test('startWork is the only thing that sets In Progress', () {
      final r = applyEvent(TaskEvent.startWork);
      expect(r.status, TaskStatus.inProgress);
      expect(r.exec, TaskExecStatus.running);
    });

    test('a run that ends without submitting yields back to the board', () {
      final r = applyEvent(TaskEvent.yieldBack);
      expect(r.status, TaskStatus.todo);
      expect(r.exec, TaskExecStatus.queued);
    });

    test('submit moves to Review/submitted', () {
      final r = applyEvent(TaskEvent.submit);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.submitted);
    });

    test('approve completes the task', () {
      final r = applyEvent(TaskEvent.approve);
      expect(r.status, TaskStatus.done);
      expect(r.exec, TaskExecStatus.done);
    });
  });

  group('engineer review majority', () {
    // Mirrors ProjectPlanningRun._review's pass rule: strict majority approve.
    bool passes(int approvals, int total) => approvals * 2 > total;

    test('strict majority', () {
      expect(passes(2, 3), isTrue); // 2 of 3
      expect(passes(1, 3), isFalse); // 1 of 3
      expect(passes(2, 4), isFalse); // tie does not pass
      expect(passes(3, 4), isTrue);
      expect(passes(1, 1), isTrue);
      expect(passes(0, 2), isFalse);
    });
  });
}
