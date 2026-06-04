// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart'
    show TasksCompanion;

import '../../../shared/ui/nexus_ui.dart';

/// Overview tab — the owner's editable view of a task: title, description,
/// priority, status, start/due dates, and assigned agent. Persists to the DB.
class OverviewTab extends ConsumerStatefulWidget {
  final int taskId;
  const OverviewTab({super.key, required this.taskId});

  @override
  ConsumerState<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<OverviewTab> {
  static const _statuses = ['Todo', 'In Progress', 'Review', 'Done', 'Blocked'];
  static const _priorities = ['HIGH', 'MED', 'LOW'];

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _status = 'Todo';
  String _priority = 'MED';
  DateTime? _startDate;
  DateTime? _dueDate;
  int? _agentId;
  String? _planPath;
  int? _chatSessionFk;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final task = await ref
        .read(nexusDatabaseProvider)
        .getTaskById(widget.taskId);
    if (!mounted || task == null) {
      setState(() => _loaded = true);
      return;
    }
    setState(() {
      _titleCtrl.text = task.title;
      _descCtrl.text = task.description ?? '';
      _status = _statuses.contains(task.status) ? task.status : 'Todo';
      _priority = _priorities.contains(task.priority) ? task.priority : 'MED';
      _startDate = task.startDate;
      _dueDate = task.dueDate;
      _agentId = task.task_agent_fk;
      _planPath = task.task_plan_path;
      _chatSessionFk = task.task_chat_session_fk;
      _loaded = true;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    // Enforce start <= due right in the picker: a start can't be later than an
    // existing due date, and a due can't be earlier than an existing start.
    final firstDate = isStart ? DateTime(2020) : (_startDate ?? DateTime(2020));
    final lastDate = isStart ? (_dueDate ?? DateTime(2100)) : DateTime(2100);
    var initial = (isStart ? _startDate : _dueDate) ?? DateTime.now();
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _startDate!.isAfter(_dueDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date can’t be after the due date.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(nexusDatabaseProvider)
          .patchTask(
            widget.taskId,
            TasksCompanion(
              title: Value(_titleCtrl.text.trim()),
              description: Value(
                _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              ),
              status: Value(_status),
              priority: Value(_priority),
              startDate: Value(_startDate),
              dueDate: Value(_dueDate),
              task_agent_fk: Value(_agentId),
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Task saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Delete "${_titleCtrl.text}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: ctx.nx.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(nexusDatabaseProvider).deleteTask(widget.taskId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task deleted.')));
    }
  }

  String _fmt(DateTime? d) => d == null
      ? 'Not set'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  /// Backtrack links: which plan + conversation produced this task.
  Widget _provenance() {
    if (_planPath == null && _chatSessionFk == null)
      return const SizedBox.shrink();
    final muted = context.nx.textMuted;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: NexusCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Provenance',
              icon: Icons.history_edu_outlined,
              dense: true,
              accent: false,
            ),
            Gap.sm,
            if (_planPath != null)
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 14, color: muted),
                  const SizedBox(width: 6),
                  const Text('From plan: ', style: TextStyle(fontSize: 12)),
                  Flexible(
                    child: Text(
                      _basename(_planPath!),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      ref
                          .read(openPlanNotifierProvider.notifier)
                          .open(_planPath);
                      ref
                          .read(planModeNotifierProvider.notifier)
                          .set(PlanMode.edit);
                      ref
                          .read(currentMainViewProvider.notifier)
                          .setView(MainView.projectPlans);
                    },
                    child: const Text('Open', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            if (_chatSessionFk != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Text(
                      'Created in coordinator conversation #$_chatSessionFk',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    final clientId = ref.watch(currentClientIdProvider);
    final personasAsync = ref.watch(agentPersonasForClientProvider(clientId));

    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            Gap.md,
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            Gap.md,
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final s in _statuses)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in _priorities)
                        DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) =>
                        setState(() => _priority = v ?? _priority),
                  ),
                ),
              ],
            ),
            Gap.md,
            Row(
              children: [
                Expanded(
                  child: _dateField(
                    'Start date',
                    _startDate,
                    () => _pickDate(isStart: true),
                    () => setState(() => _startDate = null),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _dateField(
                    'Due date',
                    _dueDate,
                    () => _pickDate(isStart: false),
                    () => setState(() => _dueDate = null),
                  ),
                ),
              ],
            ),
            Gap.md,
            personasAsync.when(
              data: (personas) {
                final items = <DropdownMenuItem<int?>>[
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  for (final p in personas)
                    DropdownMenuItem(
                      value: p.agent_pk,
                      child: Text(p.name, overflow: TextOverflow.ellipsis),
                    ),
                ];
                final valid =
                    _agentId != null &&
                        personas.any((p) => p.agent_pk == _agentId)
                    ? _agentId
                    : null;
                return DropdownButtonFormField<int?>(
                  initialValue: valid,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assigned agent',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: items,
                  onChanged: (v) => setState(() => _agentId = v),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                'Agents error: $e',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            _provenance(),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                GradientButton(
                  onPressed: _saving ? null : _save,
                  busy: _saving,
                  icon: Icons.save,
                  label: 'Save Changes',
                ),
                OutlinedButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete_outline, color: context.nx.danger),
                  label: Text(
                    'Delete Task',
                    style: TextStyle(color: context.nx.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime? value,
    VoidCallback onPick,
    VoidCallback onClear,
  ) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(_fmt(value), style: const TextStyle(fontSize: 13)),
          ),
          if (value != null)
            InkWell(onTap: onClear, child: const Icon(Icons.clear, size: 16)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onPick,
            child: const Icon(Icons.calendar_today, size: 16),
          ),
        ],
      ),
    );
  }
}
