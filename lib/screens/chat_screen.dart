
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/message.dart';
import 'package:rttext/services/beads_service.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/app_toast.dart';
import 'package:rttext/widgets/bead_icon.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/rt_icons.dart';
import 'package:rttext/widgets/rt_markdown.dart';
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

  RealtimeChannel? _typingChannel;
  bool _peerTyping = false;
  Timer? _peerTypingTimer;

  DateTime? _peerLastReadAt;
  StreamSubscription<Conversation?>? _conversationSub;

  /// Caller's bead balance; null = unknown (sending stays allowed and the
  /// 402 from the edge function is the fallback enforcement).
  int? _beads;

  /// Last seen keyboard inset; when it grows, the list re-scrolls so the
  /// newest message is never hidden behind the keyboard.
  double _lastKeyboardInset = 0;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
    _service.markAsRead(widget.chatId);
    _loadConversation();
    _listenToConversation();
  }

  void _listenToConversation() {
    _conversationSub =
        _service.watchConversation(widget.chatId).listen((conv) {
      if (!mounted || conv == null) return;
      final myUid = _myUid ?? Supabase.instance.client.auth.currentUser?.id;
      if (myUid == null) return;
      final peerReadAt = conv.peerLastReadAtFor(myUid);
      if (peerReadAt != _peerLastReadAt) {
        setState(() => _peerLastReadAt = peerReadAt);
      }
    });
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
          .select('bot_id,dm_user_id,user_id,user_last_read_at,dm_user_last_read_at')
          .eq('id', widget.chatId)
          .maybeSingle();
      if (conv != null) {
        final parsed = Conversation.fromMap(conv);
        final myUid = Supabase.instance.client.auth.currentUser?.id;
        if (myUid != null && mounted) {
          setState(() {
            _peerLastReadAt = parsed.peerLastReadAtFor(myUid);
          });
        }
      }
      final dmUserId = conv?['dm_user_id'] as String?;
      if (dmUserId != null) {
        // Human DM: free chat. Beads are never loaded here — the bead
        // balance RPC must stay unreachable on DM code paths.
        final myUid = Supabase.instance.client.auth.currentUser?.id;
        final creatorId = conv?['user_id'] as String?;
        if (!mounted) return;
        setState(() {
          _isDm = true;
          _myUid = myUid;
        });
        _initTypingChannel();
        final peerId = myUid == dmUserId ? creatorId : dmUserId;
        if (peerId == null) return;
        try {
          final peer = await Supabase.instance.client
              .from('people')
              .select('username,avatar_url')
              .eq('id', peerId)
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

  void _initTypingChannel() {
    _typingChannel =
        Supabase.instance.client.channel('chat_presence:${widget.chatId}');
    _typingChannel!
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final senderId = payload['user_id'] as String?;
            if (senderId != null && senderId != _myUid) {
              _setPeerTyping(true);
            }
          },
        )
        .onBroadcast(
          event: 'stop_typing',
          callback: (payload) {
            final senderId = payload['user_id'] as String?;
            if (senderId != null && senderId != _myUid) {
              _setPeerTyping(false);
            }
          },
        )
        .subscribe();
  }

  void _setPeerTyping(bool typing) {
    _peerTypingTimer?.cancel();
    if (typing) {
      _peerTypingTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _peerTyping = false);
      });
    }
    if (mounted) setState(() => _peerTyping = typing);
  }

  void _onTypingChanged(bool isTyping) {
    if (!_isDm || _typingChannel == null || _myUid == null) return;
    _typingChannel?.sendBroadcastMessage(
      event: isTyping ? 'typing' : 'stop_typing',
      payload: {'user_id': _myUid!},
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _peerTypingTimer?.cancel();
    _conversationSub?.cancel();
    final channel = _typingChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
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
    _onTypingChanged(false);

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
      try {
        await _service.sendMessage(widget.chatId, text,
            senderIdToWrite: _myUid);
        if (mounted) {
          setState(() {
            _pending.removeWhere((p) => p.id == optimistic.id);
          });
        }
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Message not sent',
            style: AppToastStyle.error);
      }
      return;
    }

    try {
      final row = await _service.sendMessage(widget.chatId, text);
      // Drop the optimistic copy as soon as the server row exists — don't
      // wait for the realtime echo, which can lag and show the bubble twice.
      if (mounted) {
        setState(() {
          _pending.removeWhere((p) => p.id == optimistic.id);
        });
      }
      // The persisted row arrives via the realtime stream; the returned row
      // is only used to retire the optimistic bubble above.
      assert(row.id.isNotEmpty);
    } catch (_) {
      // Leave the optimistic bubble in place; the AI retry toast below
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
      showAppToast(
        context,
        'You\u2019re out of beads — claim 20 free ones tomorrow to keep '
        'chatting',
        style: AppToastStyle.info,
        leading: const BeadIcon(size: 24),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _awaitingReply = false);
      showAppToast(
        context,
        'The bot could not reply',
        style: AppToastStyle.error,
        actionLabel: 'Retry',
        onAction: () => _generateReply(sentText),
      );
    }
  }

  void _showMessageActions(Message message, bool isMine) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy text'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: message.content));
                    showAppToast(context, 'Copied to clipboard',
                        style: AppToastStyle.info);
                  },
                ),
                if ((isMine || !_isDm) && !message.pending)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete message',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeleteMessage(message);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be deleted for everyone in this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteMessage(message.id);
        if (!mounted) return;
        showAppToast(context, 'Message deleted', style: AppToastStyle.info);
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Failed to delete message',
            style: AppToastStyle.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardInset > _lastKeyboardInset + 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _lastKeyboardInset = keyboardInset;
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
                    if (_peerTyping)
                      Text(
                        'typing…',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
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
                  _service.markAsRead(widget.chatId);
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
            onTypingChanged: _onTypingChanged,
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
      final isMine = _isMine(message);
      final isRead = isMine &&
          (_isDm
              ? (_peerLastReadAt != null &&
                  message.createdAt != null &&
                  !message.createdAt!.isAfter(_peerLastReadAt!))
              : (i < messages.length - 1 && !message.pending));
      items.add(
        _MessageBubble(
          message: message,
          botBubbleColor: botBubbleColor,
          isDm: _isDm,
          myUserId: _myUid,
          groupedWithPrev:
              !separator && prev != null && _isMine(prev) == isMine,
          isRead: isRead,
          onLongPress: () => _showMessageActions(message, isMine),
        ),
      );
    }
    if ((!_isDm && _awaitingReply) || (_isDm && _peerTyping)) {
      items.add(const TypingIndicator());
    }
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
    this.isRead = false,
    this.onLongPress,
  });

  final Message message;

  /// Owner-picked `#RRGGBB` tint for this bot's bubbles; null = theme default.
  final String? botBubbleColor;

  /// Human DM mode: sides are decided by [myUserId], not by role (both
  /// participants' messages are stored with role 'user').
  final bool isDm;
  final String? myUserId;
  final bool groupedWithPrev;
  final bool isRead;
  final VoidCallback? onLongPress;

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
    // WhatsApp-style corner: the sender's bottom corner is nearly square on
    // the first bubble of a group instead of a drawn fin (which rendered as
    // a disconnected triangle on some devices).
    final tailRadius = groupedWithPrev ? 8.0 : 5.0;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : tailRadius),
      bottomRight: Radius.circular(isUser ? tailRadius : 20),
    );

    final createdAt = message.createdAt?.toLocal();
    final timeLabel =
        createdAt != null ? DateFormat.jm().format(createdAt) : '';

    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: isUser ? 48 : 12,
            right: isUser ? 12 : 48,
            top: groupedWithPrev ? 2 : 6,
            bottom: 2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              RtMarkdownText(
                message.content,
                baseStyle:
                    theme.textTheme.bodyMedium?.copyWith(color: textColor),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    timeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: textColor.withValues(alpha: 0.65),
                    ),
                  ),
                  if (isUser) ...[
                    const SizedBox(width: 3),
                    Icon(
                      message.pending
                          ? Icons.access_time_rounded
                          : (isRead
                              ? Icons.done_all_rounded
                              : Icons.check_rounded),
                      size: isRead ? 14 : 12,
                      color: isRead
                          ? const Color(0xFF53BDEB)
                          : textColor.withValues(alpha: 0.75),
                    ),
                  ],
                ],
              ),
            ],
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
    this.onTypingChanged,
    this.enabled = true,
    this.outOfBeads = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<bool>? onTypingChanged;
  final bool enabled;
  final bool outOfBeads;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);

    if (has) {
      widget.onTypingChanged?.call(true);
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(milliseconds: 2500), () {
        widget.onTypingChanged?.call(false);
      });
    } else {
      _typingDebounce?.cancel();
      widget.onTypingChanged?.call(false);
    }
  }

  void _handleSend() {
    _typingDebounce?.cancel();
    widget.onTypingChanged?.call(false);
    widget.onSend();
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
                onSubmitted: (_) => _handleSend(),
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
                onPressed: canType && _hasText ? _handleSend : null,
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
