// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';

/// Kanban board view for the Project Overview (moved during organization refactor 2026-05).
/// Groups tasks by status columns. Supports drag-to-move between columns.
class TaskKanbanBoard extends ConsumerWidget {
  final List<dynamic> tasks; // Drift Task objects from watch
  final int? selectedTaskId;
  final Function(int) onTaskSelected;

  const TaskKanbanBoard({
    super.key,
    required this.tasks,
    required this.selectedTaskId,
    required this.onTaskSelected,
  });

  // Standard Kanban columns (can be made configurable later)
  static const List<String> _columns = [
    'Todo',
    'In Progress',
    'Review',
    'Done',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group tasks by status
    final grouped = <String, List<dynamic>>{};
    for (final col in _columns) {
      grouped[col] = [];
    }
    grouped['Other'] = []; // catch-all

    for (final task in tasks) {
      final status = (task.status as String?) ?? 'Todo';
      if (grouped.containsKey(status)) {
        grouped[status]!.add(task);
      } else {
        grouped['Other']!.add(task);
      }
    }

    // Remove empty "Other" column if nothing there
    if (grouped['Other']!.isEmpty) {
      grouped.remove('Other');
    }

    final columnKeys = grouped.keys.toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: columnKeys.map((columnName) {
        final columnTasks = grouped[columnName]!;

        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          columnName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${columnTasks.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Drop zone + cards
                Expanded(
                  child: DragTarget<int>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) {
                      final taskId = details.data;
                      _moveTaskToStatus(ref, taskId, columnName);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isActive = candidateData.isNotEmpty;

                      return Container(
                        color: isActive
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.08)
                            : Colors.transparent,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: columnTasks.length,
                          itemBuilder: (context, index) {
                            final task = columnTasks[index];
                            final isSelected = task.task_pk == selectedTaskId;

                            return _KanbanCard(
                              task: task,
                              isSelected: isSelected,
                              onTap: () => onTaskSelected(task.task_pk),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _moveTaskToStatus(
    WidgetRef ref,
    int taskId,
    String newStatus,
  ) async {
    final db = ref.read(nexusDatabaseProvider);

    // Targeted partial update — only change status
    await db.updateTaskStatus(taskId, newStatus);
  }
}

class _KanbanCard extends StatelessWidget {
  final dynamic task;
  final bool isSelected;
  final VoidCallback onTap;

  const _KanbanCard({
    required this.task,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final priority = (task.priority as String?) ?? 'MED';
    final title = task.title as String? ?? 'Untitled';

    Color priorityColor;
    switch (priority.toUpperCase()) {
      case 'HIGH':
        priorityColor = Colors.red.shade400;
        break;
      case 'MED':
        priorityColor = Colors.orange.shade400;
        break;
      default:
        priorityColor = Colors.blueGrey.shade300;
    }

    return Draggable<int>(
      data: task.task_pk as int,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: _buildCardContent(
            context,
            priorityColor,
            title,
            isSelected: false,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCardContent(
          context,
          priorityColor,
          title,
          isSelected: isSelected,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: _buildCardContent(
          context,
          priorityColor,
          title,
          isSelected: isSelected,
        ),
      ),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    Color priorityColor,
    String title, {
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
              : Theme.of(context).dividerColor.withValues(alpha: 0.6),
        ),
        boxShadow: [
          if (!isSelected)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: priorityColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '#${task.task_pk}  $title',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _SmallChip(text: task.priority ?? 'MED'),
              if (task.task_agent_fk != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.smart_toy, size: 11, color: Colors.grey),
              ],
              const Spacer(),
              if ((task.tokenCost as int? ?? 0) > 0)
                Text(
                  '${task.tokenCost}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String text;

  const _SmallChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
      ),
    );
  }
}
