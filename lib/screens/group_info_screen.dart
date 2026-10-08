import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/conversation_member.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/app_toast.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/full_screen_image_viewer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Group Info and member management screen for a group chat.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.conversationId,
    this.initialTitle,
    this.initialAvatarUrl,
  });

  final String conversationId;
  final String? initialTitle;
  final String? initialAvatarUrl;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final ConversationsService _service;

  String? _title;
  String? _avatarUrl;
  String? _createdBy;
  bool _isAdmin = false;
  bool _loading = true;

  List<ConversationMember> _members = [];
  List<Map<String, dynamic>> _sharedMedia = [];
  bool _loadingMedia = false;

  String? get _myUid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
    _title = widget.initialTitle;
    _avatarUrl = widget.initialAvatarUrl;

    _loadInfo();
    _loadSharedMedia();
  }

  Future<void> _loadInfo() async {
    try {
      final convRow = await Supabase.instance.client
          .from('conversations')
          .select('title,avatar_url,created_by')
          .eq('id', widget.conversationId)
          .maybeSingle();

      final members = await _service.getGroupMembers(widget.conversationId);

      if (!mounted) return;
      final myUid = _myUid;
      final amAdmin = convRow?['created_by'] == myUid ||
          members.any((m) => m.userId == myUid && m.isAdmin);

      setState(() {
        if (convRow != null) {
          _title = convRow['title'] as String? ?? _title;
          _avatarUrl = convRow['avatar_url'] as String? ?? _avatarUrl;
          _createdBy = convRow['created_by'] as String?;
        }
        _members = members;
        _isAdmin = amAdmin;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSharedMedia() async {
    setState(() => _loadingMedia = true);
    try {
      final media = await _service.getSharedMedia(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _sharedMedia = media;
        _loadingMedia = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMedia = false);
    }
  }

  Future<void> _removeMember(ConversationMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: const Text('They will no longer receive or send messages here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _service.removeGroupMember(member.id);
        if (!mounted) return;
        showAppToast(context, 'Member removed', style: AppToastStyle.info);
        _loadInfo();
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Failed to remove member',
            style: AppToastStyle.error);
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You will no longer participate in this group chat.'),
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
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final myMember = _members.firstWhere((m) => m.userId == _myUid);
        await _service.removeGroupMember(myMember.id);
        if (!mounted) return;
        showAppToast(context, 'You left the group', style: AppToastStyle.info);
        context.go('/chats');
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Failed to leave group',
            style: AppToastStyle.error);
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: const Text(
          'This will permanently delete the group and its message history for all members.',
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

    if (confirmed == true && mounted) {
      try {
        await _service.delete(widget.conversationId);
        if (!mounted) return;
        showAppToast(context, 'Group deleted', style: AppToastStyle.info);
        context.go('/chats');
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Failed to delete group',
            style: AppToastStyle.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupName = _title ?? 'Group Chat';
    final isCreator = _createdBy == _myUid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Group Avatar & Title
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
                        FullScreenImageViewer.open(
                          context,
                          imageUrl: _avatarUrl!,
                          heroTag: 'group-pfp-${widget.conversationId}',
                        );
                      }
                    },
                    child: Hero(
                      tag: 'group-pfp-${widget.conversationId}',
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                            ? CachedNetworkImageProvider(_avatarUrl!)
                            : null,
                        child: _avatarUrl == null || _avatarUrl!.isEmpty
                            ? Icon(
                                Icons.group_rounded,
                                size: 50,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fade(duration: Motion.standard)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                      duration: Motion.emphasized,
                      curve: Motion.springCurve,
                    ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    groupName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    '${_members.length} members',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Members Section
                Text(
                  'Members',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _members.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 64),
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      final isMe = member.userId == _myUid;

                      return ListTile(
                        leading: BotAvatar(
                          name: member.name,
                          url: member.avatarUrl,
                          radius: 20,
                        ),
                        title: Row(
                          children: [
                            Text(
                              isMe ? '${member.name} (You)' : member.name,
                              style: TextStyle(
                                fontWeight: isMe
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (member.isBot) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'BOT',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                            if (member.isAdmin) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondary
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ADMIN',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: (_isAdmin && !isMe)
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline_rounded,
                                    size: 20),
                                tooltip: 'Remove member',
                                onPressed: () => _removeMember(member),
                              )
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Shared Media Gallery
                Text(
                  'Shared Media (${_sharedMedia.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_loadingMedia)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_sharedMedia.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No photos shared yet',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _sharedMedia.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemBuilder: (context, index) {
                          final item = _sharedMedia[index];
                          final url = item['media_url'] as String? ?? '';
                          final id = item['id'] as String;

                          return GestureDetector(
                            onTap: () {
                              FullScreenImageViewer.open(
                                context,
                                imageUrl: url,
                                heroTag: 'media-$id',
                              );
                            },
                            child: Hero(
                              tag: 'media-$id',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: url,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: theme.colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image_rounded),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Actions: Leave Group / Delete Group
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.logout_rounded,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          'Leave Group',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        onTap: _leaveGroup,
                      ),
                      if (isCreator) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.delete_forever_rounded,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Delete Group',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onTap: _deleteGroup,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
