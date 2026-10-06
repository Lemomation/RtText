import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/placeholder_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Public profile of an AI character. Loads through the `public_bots` view so
/// `sys_prompt` is never present here; owners manage the character via Edit
/// (the creator screen fetches their own row, RLS-restricted).
class BotProfileScreen extends StatefulWidget {
  const BotProfileScreen({super.key, required this.botId});

  final String botId;

  @override
  State<BotProfileScreen> createState() => _BotProfileScreenState();
}

class _BotProfileScreenState extends State<BotProfileScreen> {
  Bot? _bot;
  bool _loading = true;
  bool _notFound = false;
  bool _starting = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      final bot =
          await BotsService(Supabase.instance.client).getById(widget.botId);
      if (!mounted) return;
      setState(() {
        _bot = bot;
        _loading = false;
        _notFound = bot == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  bool get _isOwner =>
      _bot != null &&
      _bot!.ownerId != null &&
      _bot!.ownerId == Supabase.instance.client.auth.currentUser?.id;

  Future<void> _startChat() async {
    final bot = _bot;
    if (bot == null || _starting) return;
    setState(() => _starting = true);
    try {
      final conversation = await ConversationsService(Supabase.instance.client)
          .getOrCreate(bot.id);
      if (!mounted) return;
      context.go('/chat/${conversation.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _confirmDelete() async {
    final bot = _bot;
    if (bot == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete character?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            )
                .animate()
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1, 1),
                  duration: 350.ms,
                  curve: Curves.easeOutBack,
                )
                .fade(duration: 250.ms),
            const SizedBox(height: 12),
            Text(
              'Chats with ${bot.name} will also be removed. This cannot be undone.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await BotsService(Supabase.instance.client).delete(bot.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded)
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1, 1),
                    duration: 350.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(width: 12),
              Expanded(child: Text('Deleted ${bot.name}')),
            ],
          ),
        ),
      );
      context.go('/discover');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Character')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound || _bot == null
              ? PlaceholderView(
                  icon: Icons.search_off_rounded,
                  label: 'Character not found',
                  actionLabel: 'Back to Discover',
                  onAction: () => context.go('/discover'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    children: [
                      Center(
                        child: Hero(
                          tag: 'bot-pfp-${_bot!.id}',
                          child: BotAvatar(
                            name: _bot!.name,
                            url: _bot!.pfpUrl,
                            radius: 56,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          _bot!.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if ((_bot!.bio ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            _bot!.bio!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                      if ((_bot!.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          _bot!.description!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      _isOwner
                          ? Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.go('/create-bot?id=${_bot!.id}'),
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text('Edit'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: theme.colorScheme.error,
                                    ),
                                    onPressed: _deleting ? null : _confirmDelete,
                                    icon: _deleting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(
                                            Icons.delete_outline_rounded),
                                    label: const Text('Delete'),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: _PressableScale(
                                onTap: _startChat,
                                child: SizedBox(
                                  width: 220,
                                  child: FilledButton.icon(
                                    onPressed: _startChat,
                                    icon: _starting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.chat_rounded),
                                    label: const Text('Start Chat'),
                                  ),
                                ),
                              ),
                            ),
                    ],
                  )
                      .animate()
                      .fade(duration: 400.ms)
                      .slideY(
                        begin: 0.03,
                        end: 0,
                        duration: 350.ms,
                        curve: Curves.easeOut,
                      ),
                ),
    );
  }
}

/// Wraps a child in a springy press-down scale for tactile feedback.
class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: 120.ms,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
