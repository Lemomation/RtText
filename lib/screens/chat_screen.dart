import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/message.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/typing_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-to-one chat thread with an AI character: realtime messages, springy
/// bubble entrances, typing indicator while the edge function generates the
/// reply, and an optimistic-send input bar.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ConversationsService _service;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  final List<Message> _pending = [];
  Bot? _bot;
  bool _awaitingReply = false;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    try {
      final conv = await Supabase.instance.client
          .from('conversations')
          .select('bot_id')
          .eq('id', widget.chatId)
          .maybeSingle();
      final botId = conv?['bot_id'] as String?;
      if (botId != null && mounted) {
        final bot = await _service.botFor(botId);
        if (mounted) setState(() => _bot = bot);
      }
    } catch (_) {
      // App bar simply keeps the generic title.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Messages more than 30 minutes apart (or crossing a day) get a separator.
  bool _needsSeparator(DateTime? prev, DateTime? time) {
    if (prev == null || time == null) return true;
    if (!_sameDay(prev, time)) return true;
    return time.difference(prev).inMinutes.abs() > 30;
  }

  String _dateSeparatorLabel(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    if (_sameDay(local, now)) return 'Today';
    if (_sameDay(local, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat.MMMd().add_jm().format(local);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: Motion.standard,
        curve: Motion.decelerateCurve,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _awaitingReply) return;
    _controller.clear();

    final optimistic = Message(
      id: 'pending-${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.chatId,
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _pending.add(optimistic);
      _awaitingReply = true;
    });
    _scrollToBottom();

    try {
      await _service.sendMessage(widget.chatId, text);
      // The persisted row arrives via the realtime stream and replaces the
      // optimistic copy.
    } catch (_) {
      // Leave the optimistic bubble in place; the AI retry snackbar below
      // still lets the user retry generation.
    }

    await _generateReply(text);
  }

  Future<void> _generateReply(String sentText) async {
    setState(() => _awaitingReply = true);
    try {
      await _service.requestAiReply(widget.chatId);
      if (!mounted) return;
      setState(() => _awaitingReply = false);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _awaitingReply = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('The bot could not reply'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _generateReply(sentText),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            BotAvatar(name: _bot?.name ?? '?', url: _bot?.pfpUrl, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _bot?.name ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_awaitingReply)
                    Text(
                      'typing…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    )
                  else if ((_bot?.bio ?? '').isNotEmpty)
                    Text(
                      _bot!.bio!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'Character profile',
            onPressed:
                _bot == null ? null : () => context.go('/bot/${_bot!.id}'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _service.watchMessages(widget.chatId),
              builder: (context, snapshot) {
                final server = snapshot.data;
                if (server == null && snapshot.hasError) {
                  return const Center(child: Text('Could not load messages'));
                }
                if (server != null) {
                  // Drop pending optimistic bubbles echoed by the server.
                  _pending.removeWhere(
                    (p) => server.any((m) => m.isUser && m.content == p.content),
                  );
                  final messages = [...server, ..._pending];
                  if (messages.isEmpty) {
                    return _EmptyThread(botName: _bot?.name);
                  }
                  _scrollToBottom();
                  return _buildList(messages);
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          _InputBar(
            controller: _controller,
            enabled: !_awaitingReply,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Message> messages) {
    final items = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final time = message.createdAt?.toLocal();
      final separator =
          _needsSeparator(prev?.createdAt?.toLocal(), time) && time != null;
      if (separator) {
        items.add(_DateSeparator(label: _dateSeparatorLabel(time)));
      }
      items.add(
        _MessageBubble(
          message: message,
          groupedWithPrev:
              !separator && prev != null && prev.isUser == message.isUser,
        ),
      );
    }
    if (_awaitingReply) items.add(const TypingIndicator());
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: items,
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ).animate().fade(duration: Motion.emphasized);
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.groupedWithPrev = false});

  final Message message;
  final bool groupedWithPrev;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : (groupedWithPrev ? 8 : 20)),
      bottomRight: Radius.circular(isUser ? (groupedWithPrev ? 8 : 20) : 20),
    );
    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 48 : 12,
          right: isUser ? 12 : 48,
          top: groupedWithPrev ? 2 : 6,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primary : theme.colorScheme.surface,
          borderRadius: radius,
        ),
        child: Text(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color:
                isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );

    return bubble
        .animate()
        .fade(duration: Motion.standard)
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1, 1),
          duration: Motion.emphasized,
          curve: Motion.springCurve,
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({this.botName});

  final String? botName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotAvatar(name: botName ?? '?', radius: 36),
          const SizedBox(height: 16),
          Text(
            'Say hi to ${botName ?? 'your bot'}!',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    ).animate().fade(duration: Motion.slow).scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: Motion.slow,
          curve: Motion.springCurve,
        );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => widget.onSend(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  suffixIcon: widget.enabled
                      ? null
                      : const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _hasText ? 0 : -0.25,
              duration: Motion.standard,
              curve: Motion.springCurve,
              child: IconButton.filled(
                onPressed: widget.enabled && _hasText ? widget.onSend : null,
                icon: const Icon(Icons.send_rounded),
                color: theme.colorScheme.onPrimary,
              ),
                )
                .animate(target: _hasText ? 1 : 0)
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                  duration: Motion.standard,
                  curve: Motion.springCurve,
                ),
          ],
        ),
      ),
    );
  }
}
