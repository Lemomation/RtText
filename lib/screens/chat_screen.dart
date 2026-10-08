
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/models/message.dart';
import 'package:rttext/services/beads_service.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/app_toast.dart';
import 'package:rttext/widgets/bead_icon.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/full_screen_image_viewer.dart';
import 'package:rttext/widgets/rt_icons.dart';
import 'package:rttext/widgets/rt_markdown.dart';
import 'package:rttext/widgets/typing_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-to-one chat thread with an AI character or (DM mode) another human:
/// realtime messages, springy bubble entrances, typing indicator while the
/// edge function generates the reply, and an optimistic-send input bar.
/// DM chats are free: they never invoke ai-reply and never touch beads.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialConversation,
  });

  final String chatId;
  final Conversation? initialConversation;

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
  String? _peerId;
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

  Message? _replyingTo;
  Uint8List? _attachedBytes;
  String? _attachedExt;
  bool _isUploadingMedia = false;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
    _myUid = Supabase.instance.client.auth.currentUser?.id;

    final init = widget.initialConversation;
    if (init != null) {
      _isDm = init.isDm;
      if (init.isDm) {
        _peerId = init.peerIdFor(_myUid ?? '');
        _peerName = init.peerName;
        _peerAvatarUrl = init.peerAvatarUrl;
        if (_myUid != null) {
          _peerLastReadAt = init.peerLastReadAtFor(_myUid!);
        }
        _initTypingChannel();
      } else if (init.botName != null) {
        _bot = Bot(
          id: init.botId,
          ownerId: init.userId,
          name: init.botName!,
          pfpUrl: init.botPfpUrl,
        );
      }
    }

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
      if (conv.isDm && (!_isDm || _peerName == null)) {
        setState(() {
          _isDm = true;
          _myUid = myUid;
        });
        _initTypingChannel();
        final peerId = conv.peerIdFor(myUid);
        if (peerId != null) {
          setState(() => _peerId = peerId);
          _fetchPeerInfo(peerId);
        }
      }
    });
  }

  Future<void> _fetchPeerInfo(String peerId) async {
    try {
      final peer = await Supabase.instance.client
          .from('people')
          .select('username,avatar_url')
          .eq('id', peerId)
          .maybeSingle();
      if (mounted && peer != null) {
        setState(() {
          _peerName = peer['username'] as String?;
          _peerAvatarUrl = peer['avatar_url'] as String?;
        });
      }
    } catch (_) {}
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
          .select('id,bot_id,dm_user_id,user_id,user_last_read_at,dm_user_last_read_at')
          .eq('id', widget.chatId)
          .maybeSingle();
      if (conv == null) return;

      final parsed = Conversation.fromMap(conv);
      final myUid = _myUid ?? Supabase.instance.client.auth.currentUser?.id;
      if (mounted) {
        setState(() {
          _myUid = myUid;
          if (myUid != null) {
            _peerLastReadAt = parsed.peerLastReadAtFor(myUid);
          }
        });
      }
      final dmUserId = parsed.dmUserId;
      if (dmUserId != null) {
        // Human DM: free chat. Beads are never loaded here — the bead
        // balance RPC must stay unreachable on DM code paths.
        if (!mounted) return;
        setState(() {
          _isDm = true;
          _myUid = myUid;
        });
        _initTypingChannel();
        final peerId = parsed.peerIdFor(myUid ?? '');
        if (peerId != null) {
          if (mounted) setState(() => _peerId = peerId);
          await _fetchPeerInfo(peerId);
        }
        return;
      }
      // Bot chat: load the bead balance while the bot metadata fetches.
      _loadBalance();
      final botId = parsed.botId;
      if (botId.isNotEmpty && mounted) {
        final bot = await _service.botFor(botId);
        if (mounted) setState(() => _bot = bot);
      }
    } catch (_) {
      // App bar simply keeps the generic title.
    }
  }

  void _initTypingChannel() {
    if (_typingChannel != null) return;
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

  void _startReply(Message message) {
    HapticFeedback.lightImpact();
    setState(() => _replyingTo = message);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last
          : 'jpg';
      if (!mounted) return;
      setState(() {
        _attachedBytes = bytes;
        _attachedExt = ext;
      });
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Could not select photo',
          style: AppToastStyle.error);
    }
  }

  void _showAttachmentPicker() {
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
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: const Text('Take photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final hasMedia = _attachedBytes != null;
    if ((text.isEmpty && !hasMedia) ||
        _awaitingReply ||
        _beads == 0 ||
        _isUploadingMedia) {
      return;
    }
    _controller.clear();
    _onTypingChanged(false);

    final bytesToUpload = _attachedBytes;
    final extToUpload = _attachedExt ?? 'jpg';
    final replyTarget = _replyingTo;

    setState(() {
      _attachedBytes = null;
      _attachedExt = null;
      _replyingTo = null;
    });

    String? uploadedUrl;
    if (bytesToUpload != null) {
      setState(() => _isUploadingMedia = true);
      try {
        uploadedUrl = await _service.uploadChatImage(
          widget.chatId,
          bytesToUpload,
          extension: extToUpload,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isUploadingMedia = false);
        showAppToast(context, 'Failed to upload photo',
            style: AppToastStyle.error);
        return;
      }
      if (mounted) setState(() => _isUploadingMedia = false);
    }

    final replySenderName = replyTarget == null
        ? null
        : (_isMine(replyTarget)
            ? 'You'
            : (_isDm ? (_peerName ?? 'Friend') : (_bot?.name ?? 'Bot')));

    final replySnippet = replyTarget == null
        ? null
        : (replyTarget.content.trim().isNotEmpty
            ? replyTarget.content
            : (replyTarget.mediaUrl != null ? '📷 Photo' : ''));

    final optimistic = Message(
      id: 'pending-${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.chatId,
      role: 'user',
      content: text,
      // DM messages carry the sender so both sides can attribute bubbles;
      // bot chats leave it null exactly as before.
      senderId: _isDm ? _myUid : null,
      mediaUrl: uploadedUrl,
      replyToId: replyTarget?.id,
      replyToContent: replySnippet,
      replyToSender: replySenderName,
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
        await _service.sendMessage(
          widget.chatId,
          text,
          senderIdToWrite: _myUid,
          mediaUrl: uploadedUrl,
          replyToId: replyTarget?.id,
          replyToContent: replySnippet,
          replyToSender: replySenderName,
        );
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
      final row = await _service.sendMessage(
        widget.chatId,
        text,
        mediaUrl: uploadedUrl,
        replyToId: replyTarget?.id,
        replyToContent: replySnippet,
        replyToSender: replySenderName,
      );
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

    await _generateReply(text.isNotEmpty ? text : '📷 [Sent a photo]');
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
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _startReply(message);
                  },
                ),
                if (message.content.trim().isNotEmpty)
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
                if (message.mediaUrl != null)
                  ListTile(
                    leading: const Icon(Icons.fullscreen_rounded),
                    title: const Text('View full photo'),
                    onTap: () {
                      Navigator.pop(ctx);
                      FullScreenImageViewer.open(
                        context,
                        imageUrl: message.mediaUrl!,
                        heroTag: 'msg-media-${message.id}',
                        caption: message.content.trim().isNotEmpty
                            ? message.content
                            : null,
                      );
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

  void _openDetails() {
    if (_isDm) {
      final pid = _peerId;
      if (pid != null) {
        final nameParam = Uri.encodeComponent(_peerName ?? '');
        final pfpParam = Uri.encodeComponent(_peerAvatarUrl ?? '');
        context.push(
          '/peer-profile/$pid?conversationId=${widget.chatId}&name=$nameParam&avatarUrl=$pfpParam',
        );
      }
    } else if (_bot != null) {
      context.push('/bot/${_bot!.id}');
    }
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
        title: InkWell(
          onTap: _openDetails,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                          ),
                      ],
                    ),
                  ),
                ] else ...[
                  BotAvatar(
                      name: _bot?.name ?? '?', url: _bot?.pfpUrl, radius: 18),
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                          )
                        else if ((_bot?.bio ?? '').isNotEmpty)
                          Text(
                            _bot!.bio!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_isDm && _peerId != null)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'Contact info',
              onPressed: _openDetails,
            )
          else if (!_isDm && _bot != null)
            IconButton(
              icon: const Icon(Icons.smart_toy_outlined),
              tooltip: 'Character profile',
              onPressed: _openDetails,
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
                        m.mediaUrl == p.mediaUrl &&
                        m.senderId == p.senderId),
                  );
                  final messages = [...server, ..._pending];
                  if (messages.isEmpty) {
                    return _EmptyThread(
                      name: _isDm ? _peerName : _bot?.name,
                      isDm: _isDm,
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
            isUploading: _isUploadingMedia,
            replyingTo: _replyingTo,
            replySender: _replyingTo == null
                ? null
                : (_isMine(_replyingTo!)
                    ? 'You'
                    : (_isDm
                        ? (_peerName ?? 'Friend')
                        : (_bot?.name ?? 'Bot'))),
            onCancelReply: _cancelReply,
            attachedBytes: _attachedBytes,
            onRemoveAttachment: () => setState(() {
              _attachedBytes = null;
              _attachedExt = null;
            }),
            onAttach: _showAttachmentPicker,
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
          onReply: () => _startReply(message),
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

/// Text color that stays legible on any bubble background.
/// Uses luminance to guarantee high contrast:
/// - Light bubbles (> 0.40 luminance) get deep charcoal / dark slate (#0F172A).
/// - Dark bubbles (<= 0.40 luminance) get pure white (#FFFFFF).
Color _onBubbleColor(Color background) {
  final luminance = background.computeLuminance();
  return luminance > 0.40 ? const Color(0xFF0F172A) : Colors.white;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.botBubbleColor,
    this.isDm = false,
    this.myUserId,
    this.groupedWithPrev = false,
    this.isRead = false,
    this.onLongPress,
    this.onReply,
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
  final VoidCallback? onReply;

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
    final textColor = _onBubbleColor(bubbleColor);
    final isBubbleLight =
        ThemeData.estimateBrightnessForColor(bubbleColor) == Brightness.light;
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

    final hasQuote = message.replyToContent != null &&
        message.replyToContent!.trim().isNotEmpty;
    final hasMedia = message.mediaUrl != null;
    final hasText = message.content.trim().isNotEmpty;

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
          padding: EdgeInsets.symmetric(
            horizontal: hasMedia && !hasText && !hasQuote ? 6 : 14,
            vertical: hasMedia && !hasText && !hasQuote ? 6 : 8,
          ),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasQuote) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Colors.black.withValues(alpha: 0.15)
                        : (isBubbleLight
                            ? Colors.black.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.12)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: isUser
                            ? textColor.withValues(alpha: 0.8)
                            : theme.colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.replyToSender ?? 'Replying',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isUser ? textColor : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message.replyToContent!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasMedia) ...[
                GestureDetector(
                  onTap: () {
                    FullScreenImageViewer.open(
                      context,
                      imageUrl: message.mediaUrl!,
                      heroTag: 'msg-media-${message.id}',
                      caption: hasText ? message.content : null,
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 290,
                        maxHeight: 320,
                      ),
                      child: Hero(
                        tag: 'msg-media-${message.id}',
                        child: CachedNetworkImage(
                          imageUrl: message.mediaUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 240,
                            height: 180,
                            color: Colors.black12,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 240,
                            height: 180,
                            color: Colors.black12,
                            child: const Center(
                              child:
                                  Icon(Icons.broken_image_rounded, size: 36),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasText) const SizedBox(height: 6),
              ],
              if (hasText)
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
                          ? (isBubbleLight
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF53BDEB))
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

    final wrapped = Dismissible(
      key: ValueKey('msg-reply-${message.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        onReply?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(
          Icons.reply_rounded,
          color: theme.colorScheme.primary,
          size: 24,
        ),
      ),
      child: bubble,
    );

    return wrapped
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
  const _EmptyThread({this.name, this.isDm = false});

  final String? name;
  final bool isDm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallbackLabel = isDm ? 'your friend' : 'your bot';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotAvatar(name: name ?? '?', radius: 36),
          const SizedBox(height: 16),
          Text(
            'Say hi to ${name ?? fallbackLabel}!',
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
    required this.onAttach,
    this.onTypingChanged,
    this.enabled = true,
    this.outOfBeads = false,
    this.isUploading = false,
    this.replyingTo,
    this.replySender,
    this.onCancelReply,
    this.attachedBytes,
    this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final ValueChanged<bool>? onTypingChanged;
  final bool enabled;
  final bool outOfBeads;
  final bool isUploading;
  final Message? replyingTo;
  final String? replySender;
  final VoidCallback? onCancelReply;
  final Uint8List? attachedBytes;
  final VoidCallback? onRemoveAttachment;

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
    final canSend = canType &&
        !widget.isUploading &&
        (_hasText || widget.attachedBytes != null);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyingTo != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Replying to ${widget.replySender ?? 'Message'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.replyingTo!.content.trim().isNotEmpty
                              ? widget.replyingTo!.content
                              : (widget.replyingTo!.mediaUrl != null
                                  ? '📷 Photo'
                                  : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cancel reply',
                    onPressed: widget.onCancelReply,
                  ),
                ],
              ),
            ),
          ],
          if (widget.attachedBytes != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      widget.attachedBytes!,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Photo attached',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Add an optional caption below',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove photo',
                    onPressed: widget.onRemoveAttachment,
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: 'Attach photo',
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: canType && !widget.isUploading
                      ? widget.onAttach
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    enabled: canType && !widget.isUploading,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    decoration: InputDecoration(
                      hintText: widget.outOfBeads
                          ? 'Out of beads…'
                          : widget.isUploading
                              ? 'Uploading photo…'
                              : widget.enabled
                                  ? (widget.attachedBytes != null
                                      ? 'Add a caption…'
                                      : 'Message…')
                                  : 'Waiting for reply…',
                      suffixIcon: widget.isUploading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (widget.enabled && !widget.outOfBeads
                              ? null
                              : const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: canSend ? 0 : -0.25,
                  duration: Motion.standard,
                  curve: Motion.springCurve,
                  child: IconButton.filled(
                    onPressed: canSend ? _handleSend : null,
                    icon: widget.isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const RtIcon(type: RtIconType.send),
                    color: theme.colorScheme.onPrimary,
                  ),
                )
                    .animate(target: canSend ? 1 : 0)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                      duration: Motion.standard,
                      curve: Motion.springCurve,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
