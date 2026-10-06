import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/message.dart';
import 'package:rttext/services/beads_service.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/bead_icon.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/rt_icons.dart';
import 'package:rttext/widgets/typing_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-to-one chat thread with an AI character or (DM mode) another human:
/// realtime messages, springy bubble entrances, typing indicator while the
/// edge function generates the reply, and an optimistic-send input bar.
/// DM chats are free: they never invoke ai-reply and never touch beads.
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

  // DM mode: the conversation is human-to-human (dm_user_id set, bot_id
  // null). Bubbles attribute via sender_id and sending persists the message
  // only — no typing indicator, no bead balance, no ai-reply.
  bool _isDm = false;
  String? _myUid;
  String? _peerName;
  String? _peerAvatarUrl;

  /// Caller's bead balance; null = unknown (sending stays allowed and the
  /// 402 from the edge function is the fallback enforcement).
  int? _beads;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
    _loadConversation();
  }

  Future<void> _loadBalance() async {
    try {
      final beads = await BeadsService(Supabase.instance.client).balance();
      if (mounted) setState(() => _beads = beads);
    } catch (_) {
      // Balance stays unknown; the server still enforces the limit.
    }
  }

  Future<void> _loadConversation() async {
    try {
      final conv = await Supabase.instance.client
          .from('conversations')
          .select('bot_id,dm_user_id')
          .eq('id', widget.chatId)
          .maybeSingle();
      final dmUserId = conv?['dm_user_id'] as String?;
      if (dmUserId != null) {
        // Human DM: free chat. Beads are never loaded here — the bead
        // balance RPC must stay unreachable on DM code paths.
        final myUid = Supabase.instance.client.auth.currentUser?.id;
        if (!mounted) return;
        setState(() {
          _isDm = true;
          _myUid = myUid;
        });
        try {
          final peer = await Supabase.instance.client
              .from('people')
              .select('username,avatar_url')
              .eq('id', dmUserId)
              .maybeSingle();
          if (mounted) {
            setState(() {
              _peerName = peer?['username'] as String?;
              _peerAvatarUrl = peer?['avatar_url'] as String?;
            });
          }
        } catch (_) {
          // App bar simply keeps the generic title.
        }
        return;
      }
      // Bot chat: load the bead balance while the bot metadata fetches.
      _loadBalance();
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
    if (text.isEmpty || _awaitingReply || _beads == 0) return;
    _controller.clear();

    final optimistic = Message(
      id: 'pending-${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.chatId,
      role: 'user',
      content: text,
      // DM messages carry the sender so both sides can attribute bubbles;
      // bot chats leave it null exactly as before.
      senderId: _isDm ? _myUid : null,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _pending.add(optimistic);
      // No typing indicator in DMs: only AI replies "type".
      if (!_isDm) _awaitingReply = true;
    });
    _scrollToBottom();

    if (_isDm) {
      // Human DM: free — persist the message and nothing else. Never
      // requestAiReply, never beads.
      final messenger = ScaffoldMessenger.of(context);
      try {
        await _service.sendMessage(widget.chatId, text,
            senderIdToWrite: _myUid);
        // The persisted row arrives via the realtime stream and replaces the
        // optimistic copy.
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Message not sent')),
        );
      }
      return;
    }

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
      final result = await _service.requestAiReply(widget.chatId);
      if (!mounted) return;
      setState(() {
        _awaitingReply = false;
        if (result.remainingBeads != null) _beads = result.remainingBeads;
      });
      _scrollToBottom();
    } on OutOfBeadsException {
      if (!mounted) return;
      setState(() {
        _awaitingReply = false;
        _beads = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              BeadIcon(size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('You\u2019re out of beads — claim 20 free ones '
                    'tomorrow to keep chatting'),
              ),
            ],
          ),
        ),
      );
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
            if (_isDm) ...[
              BotAvatar(
                name: _peerName ?? '?',
                url: _peerAvatarUrl,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _peerName ?? 'Chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ] else ...[
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
          ],
        ),
        actions: [
          // DMs have no character profile to open.
          if (!_isDm)
            IconButton(
              icon: const Icon(Icons.smart_toy_outlined),
              tooltip: 'Character profile',
              onPressed:
                  _bot == null ? null : () => context.push('/bot/${_bot!.id}'),
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
                  // Matching sender_id too keeps a DM peer's identical text
                  // from swallowing our optimistic bubble; in bot chats both
                  // sides are null, so behavior is unchanged.
                  _pending.removeWhere(
                    (p) => server.any((m) =>
                        m.isUser &&
                        m.content == p.content &&
                        m.senderId == p.senderId),
                  );
                  final messages = [...server, ..._pending];
                  if (messages.isEmpty) {
                    return _EmptyThread(
                      botName: _isDm ? _peerName : _bot?.name,
                    );
                  }
                  _scrollToBottom();
                  return _buildList(messages, _bot?.bubbleColor);
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          // Out-of-beads banner: collapse/expand between chats with balance.
          AnimatedSize(
            duration: Motion.standard,
            curve: Motion.emphasizedCurve,
            alignment: Alignment.bottomCenter,
            child: _beads == 0
                ? const _OutOfBeadsBanner()
                : const SizedBox(width: double.infinity),
          ),
          _InputBar(
            controller: _controller,
            enabled: !_awaitingReply,
            outOfBeads: _beads == 0,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  /// Which side of the screen a bubble sits on. Bot chats keep the
  /// role-based rule; DM chats attribute via sender_id == my uid.
  bool _isMine(Message m) =>
      _isDm ? m.senderId != null && m.senderId == _myUid : m.isUser;

  /// [botBubbleColor] is the bot's stored `#RRGGBB` bubble tint (null = theme
  /// default), applied to assistant bubbles only.
  Widget _buildList(List<Message> messages, String? botBubbleColor) {
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
          botBubbleColor: botBubbleColor,
          isDm: _isDm,
          myUserId: _myUid,
          groupedWithPrev:
              !separator && prev != null && _isMine(prev) == _isMine(message),
        ),
      );
    }
    if (!_isDm && _awaitingReply) items.add(const TypingIndicator());
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

/// A stored `#RRGGBB` bot bubble tint, or null when unset/malformed (the
/// bubble then falls back to the theme surface).
Color? _parseBubbleColor(String? hex) {
  if (hex == null) return null;
  final value = int.tryParse(hex.replaceFirst('#', '').trim(), radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Text color that stays legible on a custom bubble tint.
Color _onBubbleColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.botBubbleColor,
    this.isDm = false,
    this.myUserId,
    this.groupedWithPrev = false,
  });

  final Message message;

  /// Owner-picked `#RRGGBB` tint for this bot's bubbles; null = theme default.
  final String? botBubbleColor;

  /// Human DM mode: sides are decided by [myUserId], not by role (both
  /// participants' messages are stored with role 'user').
  final bool isDm;
  final String? myUserId;
  final bool groupedWithPrev;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = isDm
        ? message.senderId != null && message.senderId == myUserId
        : message.isUser;
    // Only assistant bubbles take the bot's tint; user bubbles keep the
    // accent color as-is.
    final tint = isUser ? null : _parseBubbleColor(botBubbleColor);
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : (tint ?? theme.colorScheme.surface);
    final textColor = isUser
        ? theme.colorScheme.onPrimary
        : (tint == null ? theme.colorScheme.onSurface : _onBubbleColor(tint));
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
        decoration: ShapeDecoration(
          color: bubbleColor,
          shape: _BubbleTailShape(
            radius: radius,
            showTail: !groupedWithPrev,
            tailOnRight: isUser,
          ),
        ),
        child: Text(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
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

/// The bubble's fill shape: the existing rounded-rect geometry, plus a small
/// WhatsApp-style tail hanging off the bottom corner when the message starts
/// a new group (right side for my messages, left for the other side). The
/// tail pokes ~9dp past the bubble edge and dips less than 2dp below it, so
/// the bubble's own side/bottom margins keep it clear of neighbours.
class _BubbleTailShape extends ShapeBorder {
  const _BubbleTailShape({
    required this.radius,
    required this.showTail,
    required this.tailOnRight,
  });

  final BorderRadius radius;
  final bool showTail;
  final bool tailOnRight;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path()..addRRect(radius.toRRect(rect));
    if (!showTail) return path;

    const reach = 9.0; // how far the tip pokes past the bubble edge
    // The fin wraps the bubble's bottom corner: it starts on the straight
    // side edge just above the corner, flares out to a tip level with the
    // bottom edge, and tucks back into the bottom edge. Unioning it with the
    // rounded rect blends it into the corner seamlessly.
    final tail = Path();
    if (tailOnRight) {
      tail
        ..moveTo(rect.right, rect.bottom - 9)
        ..quadraticBezierTo(
          rect.right + 2,
          rect.bottom - 3,
          rect.right + reach,
          rect.bottom + 1,
        )
        ..quadraticBezierTo(
          rect.right + 2,
          rect.bottom + 3,
          rect.right - 13,
          rect.bottom,
        );
    } else {
      tail
        ..moveTo(rect.left, rect.bottom - 9)
        ..quadraticBezierTo(
          rect.left - 2,
          rect.bottom - 3,
          rect.left - reach,
          rect.bottom + 1,
        )
        ..quadraticBezierTo(
          rect.left - 2,
          rect.bottom + 3,
          rect.left + 13,
          rect.bottom,
        );
    }
    tail.close();
    return Path.combine(PathOperation.union, path, tail);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // The fill is drawn by ShapeDecoration from [getOuterPath]; there is no
    // border to stroke.
  }

  @override
  ShapeBorder scale(double t) => this;
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

class _OutOfBeadsBanner extends StatelessWidget {
  const _OutOfBeadsBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const BeadIcon(size: 22)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.12, 1.12),
                duration: Motion.slow,
                curve: Motion.springCurve,
              ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You\u2019re out of beads — each reply costs 1. Come back '
              'tomorrow for 20 free ones.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fade(duration: Motion.standard)
        .slideY(begin: 0.2, end: 0, duration: Motion.standard);
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    this.enabled = true,
    this.outOfBeads = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final bool outOfBeads;

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
    final canType = widget.enabled && !widget.outOfBeads;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                enabled: canType,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => widget.onSend(),
                decoration: InputDecoration(
                  hintText: widget.outOfBeads
                      ? 'Out of beads…'
                      : widget.enabled
                          ? 'Message…'
                          : 'Waiting for reply…',
                  suffixIcon: widget.enabled && !widget.outOfBeads
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
                onPressed: canType && _hasText ? widget.onSend : null,
                icon: const RtIcon(type: RtIconType.send),
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
