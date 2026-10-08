import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/app_toast.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/full_screen_image_viewer.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Contact info and chat management for a 1:1 human direct message.
/// Displays peer avatar, username, member join date, shared media gallery,
/// and options to clear chat history or delete the conversation.
class PeerProfileScreen extends StatefulWidget {
  const PeerProfileScreen({
    super.key,
    required this.peerId,
    this.conversationId,
    this.initialName,
    this.initialAvatarUrl,
  });

  final String peerId;
  final String? conversationId;
  final String? initialName;
  final String? initialAvatarUrl;

  @override
  State<PeerProfileScreen> createState() => _PeerProfileScreenState();
}

class _PeerProfileScreenState extends State<PeerProfileScreen> {
  late final ConversationsService _service;

  String? _username;
  String? _avatarUrl;
  DateTime? _createdAt;

  List<Map<String, dynamic>> _sharedMedia = [];
  bool _loadingMedia = false;

  @override
  void initState() {
    super.initState();
    _service = ConversationsService(Supabase.instance.client);
    _username = widget.initialName;
    _avatarUrl = widget.initialAvatarUrl;

    _loadProfile();
    if (widget.conversationId != null) {
      _loadSharedMedia();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _service.getPeerProfile(widget.peerId);
      if (!mounted) return;
      if (profile != null) {
        setState(() {
          _username = profile['username'] as String? ?? _username;
          _avatarUrl = profile['avatar_url'] as String? ?? _avatarUrl;
          if (profile['created_at'] != null) {
            _createdAt = DateTime.tryParse(profile['created_at'] as String);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSharedMedia() async {
    setState(() => _loadingMedia = true);
    try {
      final media = await _service.getSharedMedia(widget.conversationId!);
      if (!mounted) return;
      setState(() {
        _sharedMedia = media;
        _loadingMedia = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMedia = false);
    }
  }

  void _copyUsername() {
    final name = _username;
    if (name != null && name.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: name));
      showAppToast(context, 'Username copied to clipboard',
          style: AppToastStyle.info);
    }
  }

  void _shareProfile() {
    final name = _username;
    if (name != null && name.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: '@$name on RtText'));
      showAppToast(context, 'Profile link copied to clipboard',
          style: AppToastStyle.info);
    }
  }

  Future<void> _confirmClearChat() async {
    if (widget.conversationId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'All messages in this conversation will be permanently deleted for both participants.',
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
            child: const Text('Clear Chat'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _service.clearConversationMessages(widget.conversationId!);
        if (!mounted) return;
        showAppToast(context, 'Chat history cleared',
            style: AppToastStyle.info);
        setState(() => _sharedMedia = []);
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Failed to clear chat',
            style: AppToastStyle.error);
      }
    }
  }

  Future<void> _confirmDeleteConversation() async {
    if (widget.conversationId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This chat will be removed from your conversations list.',
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
        await _service.delete(widget.conversationId!);
        if (!mounted) return;
        showAppToast(context, 'Conversation deleted',
            style: AppToastStyle.info);
        context.go('/chats');
      } catch (_) {
        if (!mounted) return;
        showAppToast(context, 'Failed to delete conversation',
            style: AppToastStyle.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = _username ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Info'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // 1. Avatar and Name Header
          Center(
            child: GestureDetector(
              onTap: () {
                if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
                  FullScreenImageViewer.open(
                    context,
                    imageUrl: _avatarUrl!,
                    heroTag: 'peer-pfp-${widget.peerId}',
                  );
                }
              },
              child: Hero(
                tag: 'peer-pfp-${widget.peerId}',
                child: BotAvatar(
                  name: displayName,
                  url: _avatarUrl,
                  radius: 54,
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
              displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              onTap: _copyUsername,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.alternate_email_rounded,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      displayName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_createdAt != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Joined ${DateFormat.yMMMM().format(_createdAt!.toLocal())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // 2. Quick Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionCard(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Message',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 16),
              _ActionCard(
                icon: Icons.copy_rounded,
                label: 'Copy Name',
                onTap: _copyUsername,
              ),
              const SizedBox(width: 16),
              _ActionCard(
                icon: Icons.share_rounded,
                label: 'Share',
                onTap: _shareProfile,
              ),
            ],
          ).animate(delay: 100.ms).fade(duration: Motion.emphasized),
          const SizedBox(height: 28),

          // 3. Shared Media Section
          Row(
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Shared Media',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_sharedMedia.isNotEmpty)
                Text(
                  '${_sharedMedia.length} photo${_sharedMedia.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingMedia)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_sharedMedia.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_outlined,
                      size: 36,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No shared photos yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _sharedMedia.length,
              itemBuilder: (context, index) {
                final item = _sharedMedia[index];
                final mediaUrl = item['media_url'] as String? ?? '';
                final caption = item['content'] as String?;
                return GestureDetector(
                  onTap: () {
                    FullScreenImageViewer.open(
                      context,
                      imageUrl: mediaUrl,
                      heroTag: 'shared-media-${item['id']}',
                      caption: caption,
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Hero(
                      tag: 'shared-media-${item['id']}',
                      child: CachedNetworkImage(
                        imageUrl: mediaUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.black12,
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 32),

          // 4. Chat Settings & Management Section
          if (widget.conversationId != null) ...[
            Text(
              'Chat Management',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.cleaning_services_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Clear chat history',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text('Delete messages in this chat'),
                    onTap: _confirmClearChat,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete conversation',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text('Remove from your conversations list'),
                    onTap: _confirmDeleteConversation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
