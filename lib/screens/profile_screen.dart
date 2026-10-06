
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/profile.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in user profile: avatar + username (both editable), animated
/// credits counter, the user's own characters, and sign-out with a confirm
/// dialog.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  List<Bot> _myBots = const [];
  bool _loading = true;
  bool _failed = false;

  bool _editingName = false;
  bool _savingName = false;
  final _nameController = TextEditingController();

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final client = Supabase.instance.client;
      final row =
          await client.from('profiles').select().eq('id', uid).maybeSingle();
      final bots = await BotsService(client).listMine();
      if (!mounted) return;
      setState(() {
        _profile = row == null ? null : Profile.fromMap(row);
        _myBots = bots;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pickAvatar() async {
    final uid = _uid;
    if (uid == null) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = Supabase.instance.client;
      final path = 'user/$uid.jpg';
      final bytes = await file.readAsBytes();
      await client.storage.from('pfp').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      final url = client.storage.from('pfp').getPublicUrl(path);
      await client
          .from('profiles')
          .update({'avatar_url': url}).eq('id', uid);
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Avatar update failed: $e')),
      );
    }
  }

  Future<void> _saveName() async {
    final username = _nameController.text.trim();
    final uid = _uid;
    if (username.isEmpty ||
        uid == null ||
        username == _profile?.username) {
      if (mounted) setState(() => _editingName = false);
      return;
    }
    setState(() => _savingName = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'username': username}).eq('id', uid);
      await _load();
      if (!mounted) return;
      setState(() => _editingName = false);
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded)
                  .animate()
                  .scale(
                    begin: const Offset(0.4, 0.4),
                    end: const Offset(1, 1),
                    duration: Motion.emphasized,
                    curve: Motion.springCurve,
                  ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Username updated')),
            ],
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save username — it may already be taken'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.logout_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            )
                .animate()
                .scale(
                  begin: const Offset(0.5, 0.5),
                  end: const Offset(1, 1),
                  duration: Motion.emphasized,
                  curve: Motion.springCurve,
                )
                .fade(duration: Motion.standard),
            const SizedBox(height: 12),
            const Text('You can sign back in anytime.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthController>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load your profile'),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () {
                          setState(() => _loading = true);
                          _load();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  children: [
                    Center(
                      child: PressableScale(
                        onTap: _pickAvatar,
                        child: Stack(
                          children: [
                            _ProfileAvatar(
                              url: _profile?.avatarUrl,
                              fallbackText: (_profile?.username.isNotEmpty ??
                                      false)
                                  ? _profile!.username.characters.first
                                      .toUpperCase()
                                  : '?',
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 15,
                                backgroundColor: theme.colorScheme.primary,
                                child: Icon(
                                  Icons.add_a_photo_rounded,
                                  size: 16,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fade(duration: Motion.emphasized)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1, 1),
                          duration: Motion.slow,
                          curve: Motion.springCurve,
                        ),
                    const SizedBox(height: 16),
                    // Smooth expand/collapse between the username display and
                    // the inline edit field.
                    AnimatedSize(
                      duration: Motion.standard,
                      curve: Motion.emphasizedCurve,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: Motion.standard,
                        switchInCurve: Motion.emphasizedCurve,
                        switchOutCurve: Motion.emphasizedCurve.flipped,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _editingName
                            ? Row(
                                key: const ValueKey('username-edit'),
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const Key('username-field'),
                                      controller: _nameController,
                                      autofocus: true,
                                      maxLength: 24,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) => _saveName(),
                                      decoration: const InputDecoration(
                                        labelText: 'Username',
                                        counterText: '',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('save-username'),
                                    icon: _savingName
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.check_rounded),
                                    onPressed: _savingName ? null : _saveName,
                                  ),
                                ],
                              )
                            : Row(
                                key: const ValueKey('username-display'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _profile?.username ?? 'Anonymous',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded,
                                        size: 18),
                                    tooltip: 'Edit username',
                                    onPressed: () {
                                      _nameController.text =
                                          _profile?.username ?? '';
                                      setState(() => _editingName = true);
                                    },
                                  ),
                                ],
                              ),
                      ),
                    )
                        .animate(delay: 80.ms)
                        .fade(duration: Motion.emphasized),
                    const SizedBox(height: 8),
                    Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.stars_rounded,
                                color: theme.colorScheme.primary,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              TweenAnimationBuilder<int>(
                                tween: IntTween(
                                  begin: 0,
                                  end: _profile?.credits ?? 0,
                                ),
                                duration: 800.ms,
                                curve: Motion.decelerateCurve,
                                builder: (context, value, _) => Text(
                                  '$value',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'credits',
                                style:
                                    theme.textTheme.bodyMedium?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fade(delay: 150.ms, duration: Motion.slow),
                    const SizedBox(height: 28),
                    Text('My bots', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 116,
                      child: _myBots.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                'You haven\u2019t created any characters yet.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _myBots.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 16),
                              itemBuilder: (context, index) {
                                final bot = _myBots[index];
                                return GestureDetector(
                                  onTap: () => context.push('/bot/${bot.id}'),
                                  child: SizedBox(
                                    width: 76,
                                    child: Column(
                                      children: [
                                        BotAvatar(
                                          name: bot.name,
                                          url: bot.pfpUrl,
                                          radius: 30,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          bot.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                    .animate(delay: Motion.stagger(index, stepMs: 60))
                                    .fade(duration: Motion.emphasized)
                                    .slideY(
                                      begin: 0.1,
                                      end: 0,
                                      duration: Motion.emphasized,
                                      curve: Motion.decelerateCurve,
                                    );
                              },
                            ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _confirmSignOut,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sign out'),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({this.url, required this.fallbackText});

  final String? url;
  final String fallbackText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 48,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      foregroundImage: (url != null && url!.isNotEmpty)
          ? NetworkImage(url!)
          : null,
      onForegroundImageError: (_, __) {},
      child: Text(
        fallbackText,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 30,
        ),
      ),
    );
  }
}
