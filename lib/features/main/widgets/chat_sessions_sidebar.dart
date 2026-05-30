// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexus_projects_client/core/providers/app_shell_provider.dart';
import 'package:nexus_projects_client/core/providers/database_provider.dart';
import 'package:nexus_projects_client/infrastructure/database/nexus_database.dart' show ChatSessionsCompanion;

/// Right sidebar listing the persisted Coordinator chat sessions for the
/// current project (Client → Project → Session). Selecting one sets the active
/// session that the coordinator chat screen opens.
class ChatSessionsSidebar extends ConsumerWidget {
  const ChatSessionsSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = ref.watch(currentProjectIdProvider);
    final sessionsAsync = ref.watch(chatSessionsForProjectProvider(projectId));
    final activeId = ref.watch(currentChatSessionProvider(projectId));

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 18),
                const SizedBox(width: 8),
                Text('Chat Sessions', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'New Session',
                  onPressed: () => _newSession(ref, projectId),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: sessionsAsync.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No conversations yet.\nTap + (or "Talk to Coordinator") to start one.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, i) {
                    final s = sessions[i];
                    final selected = s.session_pk == activeId;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      leading: Icon(
                        selected ? Icons.chat : Icons.chat_outlined,
                        size: 18,
                        color: selected ? Theme.of(context).colorScheme.primary : null,
                      ),
                      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: _SessionSubtitle(sessionId: s.session_pk, updatedAt: s.updatedAt),
                      onTap: () =>
                          ref.read(currentChatSessionProvider(projectId).notifier).select(s.session_pk),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        tooltip: 'Delete session',
                        onPressed: () => _deleteSession(ref, projectId, s.session_pk, activeId),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $e', style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _newSession(WidgetRef ref, int projectId) async {
    final db = ref.read(nexusDatabaseProvider);
    final id = await db.createChatSession(ChatSessionsCompanion.insert(
      project_fk: projectId,
    ));
    ref.read(currentChatSessionProvider(projectId).notifier).select(id);
  }

  Future<void> _deleteSession(WidgetRef ref, int projectId, int sessionId, int? activeId) async {
    final db = ref.read(nexusDatabaseProvider);
    await db.deleteChatSession(sessionId);
    if (activeId == sessionId) {
      ref.read(currentChatSessionProvider(projectId).notifier).select(null);
    }
  }
}

/// Live message count + relative "updated" time for a session row.
class _SessionSubtitle extends ConsumerWidget {
  final int sessionId;
  final DateTime updatedAt;
  const _SessionSubtitle({required this.sessionId, required this.updatedAt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgs = ref.watch(chatMessagesForSessionProvider(sessionId));
    final count = msgs.maybeWhen(data: (m) => m.length, orElse: () => null);
    final countStr = count != null ? '$count msg${count == 1 ? '' : 's'} • ' : '';
    return Text('$countStr${_relativeTime(updatedAt)}', style: const TextStyle(fontSize: 11));
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.month}/${t.day}';
  }
}
