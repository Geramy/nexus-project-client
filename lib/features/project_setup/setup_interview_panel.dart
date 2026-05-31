// Copyright (c) 2026 Geramy Loveless DBA Nexus Projects.
// Author: Geramy Loveless <support@nexus-projects.ai>
// Licensed under the Sustainable Use License. See LICENSE.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/audio_recorder_service.dart';
import '../../services/audio/coordinator_duplex_voice_session.dart'
    show VoiceState;
import '../../widgets/live_mic_visualizer.dart';
import 'setup_chat_controller.dart';

/// The Project Setup interview, rendered as a chat in the MainShell right outer
/// panel. Shows the full back-and-forth — thinking, tool calls, and inline
/// multiple-choice questions (which stay in the transcript, so a question is
/// never lost by clicking away). Shares state with the Tag Board via
/// [setupChatControllerProvider].
class SetupInterviewPanel extends ConsumerStatefulWidget {
  const SetupInterviewPanel({
    super.key,
    required this.projectId,
    required this.clientId,
  });

  final int projectId;
  final int clientId;

  @override
  ConsumerState<SetupInterviewPanel> createState() =>
      _SetupInterviewPanelState();
}

class _SetupInterviewPanelState extends ConsumerState<SetupInterviewPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  ({int projectId, int clientId}) get _key =>
      (projectId: widget.projectId, clientId: widget.clientId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(setupChatControllerProvider(_key)).restoreOnce();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(setupChatControllerProvider(_key)).send(text);
  }

  Future<void> _toggleCall() async {
    final controller = ref.read(setupChatControllerProvider(_key));
    if (controller.callActive) {
      await controller.endVoiceCall();
    } else {
      await controller.startVoiceCall();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ref.watch(setupChatControllerProvider(_key));
    final messages = controller.messages;

    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToEnd();
    }

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.forum_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Setup interview',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: controller.callActive
                      ? 'End voice call'
                      : 'Start voice call (hands-free interview)',
                  visualDensity: VisualDensity.compact,
                  onPressed: controller.busy && !controller.callActive
                      ? null
                      : _toggleCall,
                  icon: Icon(
                    controller.callActive ? Icons.call_end : Icons.call,
                    size: 18,
                    color: controller.callActive
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          if (controller.error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Text(controller.error!,
                  style:
                      TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          Expanded(
            child: messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => _MessageView(
                      msg: messages[i],
                      onAnswer: controller.answerQuestion,
                    ),
                  ),
          ),
          if (controller.busy) const LinearProgressIndicator(minHeight: 2),
          if (controller.callActive)
            _CallBar(
              state: controller.voiceState,
              recorder: controller.voiceRecorder,
              onEnd: _toggleCall,
            ),
          const Divider(height: 1),
          _Composer(
            controller: _input,
            busy: controller.busy,
            onSend: _send,
            hintText: controller.refining
                ? 'Describe your UI, screens, behavior, data…'
                : 'Tell the setup host about your project…',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined,
                size: 36, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              'Tell the setup host about your project to start the interview. '
              'It asks short multiple-choice questions and proposes tags on the '
              'board as you go.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.msg, required this.onAnswer});

  final SetupMsg msg;
  final void Function(SetupMsg msg, List<String> picks) onAnswer;

  @override
  Widget build(BuildContext context) {
    switch (msg.kind) {
      case SetupMsgKind.user:
        return _Bubble(text: msg.text, isUser: true);
      case SetupMsgKind.assistant:
        return _Bubble(text: msg.text, isUser: false);
      case SetupMsgKind.thinking:
        return _ThinkingTile(text: msg.text);
      case SetupMsgKind.tool:
        return _NoteRow(icon: Icons.build_outlined, text: msg.text);
      case SetupMsgKind.system:
        return _NoteRow(icon: Icons.check_circle_outline, text: msg.text);
      case SetupMsgKind.question:
        return _QuestionCard(msg: msg, onAnswer: onAnswer);
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _ThinkingTile extends StatefulWidget {
  const _ThinkingTile({required this.text});
  final String text;
  @override
  State<_ThinkingTile> createState() => _ThinkingTileState();
}

class _ThinkingTileState extends State<_ThinkingTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.outline;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right,
                    size: 16, color: muted),
                Icon(Icons.psychology_outlined, size: 14, color: muted),
                const SizedBox(width: 4),
                Text('Thinking',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2, right: 8),
              child: SelectableText(
                widget.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline multiple-choice question. Stays in the transcript; once answered it
/// locks and shows the choice, so it's never lost by clicking away.
class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.msg, required this.onAnswer});

  final SetupMsg msg;
  final void Function(SetupMsg msg, List<String> picks) onAnswer;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.msg;
    final answered = msg.answered;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(msg.text,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          if (answered)
            Text(
              msg.selected.isEmpty
                  ? 'Skipped.'
                  : 'You picked: ${msg.selected.join(', ')}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            )
          else if (msg.multi)
            ...[
              for (final option in msg.options)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(option, style: const TextStyle(fontSize: 13)),
                  value: _selected.contains(option),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(option);
                    } else {
                      _selected.remove(option);
                    }
                  }),
                ),
            ]
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in msg.options)
                  ChoiceChip(
                    label: Text(option),
                    selected: _selected.contains(option),
                    onSelected: (_) => setState(() => _selected
                      ..clear()
                      ..add(option)),
                  ),
              ],
            ),
          if (!answered) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => widget.onAnswer(msg, const []),
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => widget.onAnswer(msg, _selected.toList()),
                  child: const Text('Answer'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Active-call status strip: shows the live voice state, a mic visualizer, and
/// an end-call button while hands-free "call mode" is running.
class _CallBar extends StatelessWidget {
  const _CallBar({
    required this.state,
    required this.recorder,
    required this.onEnd,
  });

  final VoiceState state;
  final AudioRecorderService? recorder;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      VoiceState.idle => ('Connecting…', theme.colorScheme.outline),
      VoiceState.listening => ('Listening…', theme.colorScheme.primary),
      VoiceState.processing => ('Thinking…', theme.colorScheme.tertiary),
      VoiceState.speaking => ('Speaking…', theme.colorScheme.secondary),
      VoiceState.error => ('Voice error', theme.colorScheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.labelMedium?.copyWith(color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: LiveMicVisualizer(
              recorder: recorder,
              color: color,
              height: 28,
              barCount: 16,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'End call',
            visualDensity: VisualDensity.compact,
            onPressed: onEnd,
            icon: Icon(Icons.call_end, size: 18, color: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.hintText,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !busy,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: hintText,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          busy
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton.filled(
                  onPressed: onSend,
                  icon: const Icon(Icons.send, size: 18),
                ),
        ],
      ),
    );
  }
}
