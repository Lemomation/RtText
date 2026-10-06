import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/placeholder_view.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:rttext/widgets/rt_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chats tab: realtime list of conversations with swipe-to-delete and undo.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late final ConversationsService _service;
  List<Conversation>? _cached;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final local = time.toLocal();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return DateFormat.Hm().format(local);
    if (diff.inDays < 7) return DateFormat.E().format(local);
    return DateFormat.MMMd().format(local);
  }

  Future<void> _delete(Conversation conversation) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.delete(conversation.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Deleted chat with ${conversation.isDm
                ? (conversation.peerName ?? 'them')
                : (conversation.botName ?? 'bot')}',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                // Restore the row in its original orientation: a DM is
                // identified by dm_user_id (either side may have deleted it),
                // a bot chat by bot_id.
                await Supabase.instance.client.from('conversations').insert({
                  'user_id': conversation.userId,
                  if (conversation.isDm)
                    'dm_user_id': conversation.dmUserId
                  else
                    'bot_id': conversation.botId,
                });
              } catch (_) {}
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('RtText'),
        actions: [
          IconButton(
            icon: const RtIcon(type: RtIconType.person),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-bot'),
        child: const RtIcon(type: RtIconType.plus),
      )
          .animate()
          .fade(delay: 300.ms, duration: Motion.slow)
          .scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1, 1),
            duration: Motion.slow,
            curve: Motion.springCurve,
          ),
      body: StreamBuilder<List<Conversation>>(
        stream: _service.watchConversations(),
        initialData: _cached,
        builder: (context, snapshot) {
          final conversations = snapshot.data;
          if (conversations == null && snapshot.hasError) {
            return const PlaceholderView(
              icon: Icons.cloud_off,
              label: 'Could not load chats',
            );
          }
          if (conversations != null) _cached = conversations;
          if (conversations == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (conversations.isEmpty) {
            return Column(
              key: const Key('empty-chats'),
              children: [
                const Expanded(
                  child: PlaceholderView(
                    icon: Icons.forum_outlined,
                    label: 'No chats yet — find a bot in Discover',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: FilledButton.icon(
                    onPressed: () => context.go('/discover'),
                    icon: const Icon(Icons.explore_rounded),
                    label: const Text('Find a bot in Discover'),
                  ),
                ),
              ],
            ).animate().fade(duration: 450.ms);
          }
          return RefreshIndicator(
            onRefresh: _service.fetchConversations,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: conversations.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 76),
              itemBuilder: (context, index) {
                final c = conversations[index];
                return Dismissible(
                  key: ValueKey('conv-${c.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: theme.colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  onDismissed: (_) => _delete(c),
                  child: _ChatTile(
                    conversation: c,
                    timeLabel: _timeLabel(c.lastMessageAt ?? c.createdAt),
                    index: index,
                    onTap: () => context.push('/chat/${c.id}'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.conversation,
    required this.timeLabel,
    required this.index,
    required this.onTap,
  });

  final Conversation conversation;
  final String timeLabel;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      onTap: onTap,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: BotAvatar(
          name: conversation.isDm
              ? (conversation.peerName ?? '?')
              : (conversation.botName ?? '?'),
          url: conversation.isDm
              ? conversation.peerAvatarUrl
              : conversation.botPfpUrl,
          radius: 26,
        ),
        title: Text(
          conversation.isDm
              ? (conversation.peerName ?? 'Unknown user')
              : (conversation.botName ?? 'Unknown bot'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          conversation.lastMessagePreview ?? 'Start the conversation',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            )
                .animate(delay: Motion.stagger(index))
                .fade(duration: Motion.standard)
                .slideX(
                  begin: -0.6,
                  end: 0,
                  duration: Motion.emphasized,
                  curve: Motion.emphasizedCurve,
                ),
          ],
        ),
      ),
    )
        .animate(delay: Motion.stagger(index))
        .fade(duration: Motion.emphasized)
        .slideX(
          begin: 0.05,
          end: 0,
          duration: Motion.emphasized,
          curve: Motion.decelerateCurve,
        );
  }
}
