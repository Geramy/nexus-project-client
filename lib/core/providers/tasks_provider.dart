// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/infrastructure/models/ui/task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tasks_provider.g.dart';

@riverpod
class TasksNotifier extends _$TasksNotifier {
  @override
  List<Task> build() {
    // Seed with hierarchical demo data (linked to the Mastermind / Project Plan concept)
    return [
      Task(
        id: '884',
        title: 'Refactor JWT validation + add refresh token rotation',
        description: 'Improve JWT handling...',
        status: 'Agent Active',
        priority: 'HIGH',
        parentId: null,
        childIds: ['884-1', '884-2'],
      ),
      Task(
        id: '884-1',
        title: 'Design new refresh token flow',
        description: '',
        status: 'Done',
        priority: 'HIGH',
        parentId: '884',
      ),
      Task(
        id: '884-2',
        title: 'Implement rotation logic + tests',
        description: '',
        status: 'In Progress',
        priority: 'HIGH',
        parentId: '884',
        childIds: ['884-2-1'],
      ),
      Task(
        id: '884-2-1',
        title: 'Write security tests for rotation',
        description: '',
        status: 'Agent Active',
        priority: 'MED',
        parentId: '884-2',
      ),
      Task(
        id: '883',
        title: 'Add matrix build support for iOS + Android',
        description: '',
        status: 'In Progress',
        priority: 'MED',
        parentId: null,
      ),
    ];
  }

  void addTask(Task task) {
    state = [...state, task];
  }

  void updateTask(Task updated) {
    state = state.map((t) => t.id == updated.id ? updated : t).toList();
  }

  void deleteTask(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void selectTask(String id) {
    // This is mostly handled by the shell provider, but we can sync here if needed
  }
}
