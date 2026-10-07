
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/core/accents.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/profile.dart';
import 'package:rttext/providers/theme_provider.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/services/updater_service.dart';
import 'package:rttext/widgets/app_toast.dart';
import 'package:rttext/widgets/bead_icon.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in user profile: avatar + username (both editable), animated
/// beads counter, the user's own characters, and sign-out with a confirm
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

  final _updater = UpdaterService();
  String _installedVersion = '';
  _UpdateStage _updateStage = _UpdateStage.idle;
  UpdateInfo? _updateInfo;
  File? _updateApk;
  int _received = 0;
  int _total = 0;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
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
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Avatar update failed — try a different picture',
          style: AppToastStyle.error);
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

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _installedVersion = info.version);
    } catch (_) {
      // Version stays hidden where PackageInfo is unavailable (e.g. tests).
    }
  }

  Future<void> _checkForUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updateStage = _UpdateStage.checking);
    try {
      final info = await _updater.check();
      if (!mounted) return;
      if (info.status == UpdateStatus.upToDate) {
        setState(() => _updateStage = _UpdateStage.idle);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You\u2019re on the latest version'),
          ),
        );
        return;
      }
      setState(() {
        _updateInfo = info;
        _updateStage = _UpdateStage.available;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _updateStage = _UpdateStage.idle);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Could not check for updates — check your connection and try again'),
        ),
      );
    }
  }

  Future<void> _downloadUpdate() async {
    final url = _updateInfo?.downloadUrl;
    if (url == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _updateStage = _UpdateStage.downloading;
      _received = 0;
      _total = 0;
    });
    try {
      final apk = await _updater.download(
        url,
        onProgress: (received, total) {
          if (!mounted || (received == _received && total == _total)) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _updateApk = apk;
        _updateStage = _UpdateStage.downloaded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _updateStage = _UpdateStage.available);
      messenger.showSnackBar(
        const SnackBar(content: Text('Download failed — try again')),
      );
    }
  }

  Future<void> _installUpdate() async {
    final apk = _updateApk;
    if (apk == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _updater.install(apk);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Install failed — allow installs from this app in system settings'),
        ),
      );
    }
  }

  Widget _updateAction(ThemeData theme) {
    switch (_updateStage) {
      case _UpdateStage.checking:
        return const SizedBox(
          key: ValueKey('update-checking'),
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _UpdateStage.available:
        return SizedBox(
          key: const ValueKey('update-available'),
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _downloadUpdate,
            icon: const Icon(Icons.download_rounded),
            label: Text('Download update v${_updateInfo!.latestVersion}'),
          ),
        );
      case _UpdateStage.downloading:
        return Column(
          key: const ValueKey('update-downloading'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: _total > 0 ? _received / _total : null,
            ),
            const SizedBox(height: 8),
            Text(
              _total > 0
                  ? '${(_received / 1048576).toStringAsFixed(1)} of '
                      '${(_total / 1048576).toStringAsFixed(1)} MB'
                  : '${(_received / 1048576).toStringAsFixed(1)} MB',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case _UpdateStage.downloaded:
        return SizedBox(
          key: const ValueKey('update-downloaded'),
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _installUpdate,
            icon: const Icon(Icons.install_mobile_rounded),
            label: const Text('Install update'),
          ),
        );
      case _UpdateStage.idle:
        return SizedBox(
          key: const ValueKey('update-idle'),
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _checkForUpdate,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check for updates'),
          ),
        );
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
    final accentId = context.watch<ThemeProvider>().accentId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          // Distinctly styled action: the glyph sits in a small tonal chip
          // instead of floating bare in the app bar.
          IconButton(
            icon: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.logout_rounded, size: 20),
            ),
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
                  // Bottom padding includes the system-nav inset so the
                  // sign-out button clears the on-screen navigation bar.
                  padding: EdgeInsets.fromLTRB(
                      24,
                      16,
                      24,
                      16 +
                          MediaQuery.of(context).padding.bottom +
                          MediaQuery.of(context).viewInsets.bottom),
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
                                    icon: Container(
                                      width: 30,
                                      height: 30,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.12),
                                      ),
                                      child: const Icon(
                                        Icons.edit_rounded,
                                        size: 16,
                                      ),
                                    ),
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
                              const BeadIcon(size: 32),
                              const SizedBox(width: 12),
                              TweenAnimationBuilder<int>(
                                tween: IntTween(
                                  begin: 0,
                                  end: _profile?.beads ?? 0,
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
                                'beads',
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
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: theme
                                      .colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  child: Icon(
                                    Icons.palette_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Appearance',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final accent in accents)
                                  _AccentSwatch(
                                    accent: accent,
                                    selected: accent.id == accentId,
                                    onTap: () => context
                                        .read<ThemeProvider>()
                                        .setAccent(accent.id),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ).animate().fade(delay: 180.ms, duration: Motion.slow),
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
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: theme
                                      .colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  child: Icon(
                                    Icons.system_update_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'App updates',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (_installedVersion.isNotEmpty)
                                  Text(
                                    'v$_installedVersion',
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            AnimatedSwitcher(
                              duration: Motion.standard,
                              switchInCurve: Motion.emphasizedCurve,
                              switchOutCurve: Motion.emphasizedCurve.flipped,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, 0.25),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                              child: _updateAction(theme),
                            ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fade(delay: 200.ms, duration: Motion.slow),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: PressableScale(
                        onTap: _confirmSignOut,
                        child: OutlinedButton.icon(
                          onPressed: _confirmSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Lifecycle of the app-update card: check → download → install handoff.
enum _UpdateStage { idle, checking, available, downloading, downloaded }

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

/// One tappable 44px accent circle. The selected preset shows a check that
/// pops in with a spring, matching the motion vocabulary used elsewhere.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final Accent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: accent.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.color,
              shape: BoxShape.circle,
            ),
            child: selected
                ? Center(
                    child: Icon(
                      Icons.check_rounded,
                      size: 22,
                      color: Theme.of(context).colorScheme.onPrimary,
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.4, 0.4),
                          end: const Offset(1, 1),
                          duration: Motion.emphasized,
                          curve: Motion.springCurve,
                        ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
