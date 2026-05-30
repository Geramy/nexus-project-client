// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_projects_client/features/projects/task_workflow.dart';

void main() {
  group('applyEvent', () {
    test('startWork → In Progress / running', () {
      final r = applyEvent(TaskEvent.startWork);
      expect(r.status, TaskStatus.inProgress);
      expect(r.exec, TaskExecStatus.running);
    });

    test('submit → Review / submitted', () {
      final r = applyEvent(TaskEvent.submit);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.submitted);
    });

    test('beginVerify → Review / verifying', () {
      final r = applyEvent(TaskEvent.beginVerify);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.verifying);
    });

    test('verdictPass → Review / verified (awaits build or merge)', () {
      final r = applyEvent(TaskEvent.verdictPass);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.verified);
    });

    test('verdictFail → back to Todo / failed', () {
      final r = applyEvent(TaskEvent.verdictFail);
      expect(r.status, TaskStatus.todo);
      expect(r.exec, TaskExecStatus.failed);
    });

    test('beginBuild → Review / building', () {
      final r = applyEvent(TaskEvent.beginBuild);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.building);
    });

    test('buildPass → Review / built (awaits merge)', () {
      final r = applyEvent(TaskEvent.buildPass);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.built);
    });

    test('buildFail → back to Todo / failed', () {
      final r = applyEvent(TaskEvent.buildFail);
      expect(r.status, TaskStatus.todo);
      expect(r.exec, TaskExecStatus.failed);
    });

    test('beginMerge → Review / merging', () {
      final r = applyEvent(TaskEvent.beginMerge);
      expect(r.status, TaskStatus.review);
      expect(r.exec, TaskExecStatus.merging);
    });

    test('approve → Done / done', () {
      final r = applyEvent(TaskEvent.approve);
      expect(r.status, TaskStatus.done);
      expect(r.exec, TaskExecStatus.done);
    });

    test('reject → Todo / idle', () {
      final r = applyEvent(TaskEvent.reject);
      expect(r.status, TaskStatus.todo);
      expect(r.exec, TaskExecStatus.idle);
    });

    test('every event yields a non-empty status/exec pair', () {
      for (final e in TaskEvent.values) {
        final r = applyEvent(e);
        expect(r.status, isNotEmpty);
        expect(r.exec, isNotEmpty);
      }
    });
  });
}
