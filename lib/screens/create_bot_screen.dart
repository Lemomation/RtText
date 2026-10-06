import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/core/uuid.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/widgets/placeholder_view.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Character creator / editor. Create mode is at `/create-bot`; edit mode
/// passes the bot id as `/create-bot?id=<botId>`. In edit mode the owner's
/// row (including `sys_prompt`) is fetched directly from `bots` — RLS only
/// permits that read for the owner, so non-owners never see the prompt.
class CreateBotScreen extends StatefulWidget {
  const CreateBotScreen({super.key, this.botId});

  final String? botId;

  @override
  State<CreateBotScreen> createState() => _CreateBotScreenState();
}

class _CreateBotScreenState extends State<CreateBotScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sysPromptController = TextEditingController();

  XFile? _pickedPfp;
  String? _existingPfpUrl;
  bool _loadingEdit = false;
  bool _editFailed = false;
  bool _submitting = false;
  bool _succeeded = false;

  bool get _isEdit => widget.botId != null;

  @override
  void initState() {
    super.initState();
    // Keep the avatar's fallback initial in sync with the name field.
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    if (_isEdit) _loadBot();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _descriptionController.dispose();
    _sysPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadBot() async {
    setState(() => _loadingEdit = true);
    try {
      final bot = await BotsService(Supabase.instance.client)
          .getOwnedById(widget.botId!);
      if (!mounted) return;
      if (bot == null) {
        setState(() {
          _editFailed = true;
          _loadingEdit = false;
        });
        return;
      }
      _nameController.text = bot.name;
      _bioController.text = bot.bio ?? '';
      _descriptionController.text = bot.description ?? '';
      _sysPromptController.text = bot.sysPrompt ?? '';
      _existingPfpUrl = bot.pfpUrl;
      setState(() => _loadingEdit = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _editFailed = true;
        _loadingEdit = false;
      });
    }
  }

  Future<void> _pickPfp() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file != null) setState(() => _pickedPfp = file);
  }

  /// Uploads the picked avatar to the `pfp` bucket and returns its public URL.
  Future<String?> _uploadPfp(XFile file) async {
    final client = Supabase.instance.client;
    final path = 'bot/${uuidV4()}.jpg';
    final bytes = await file.readAsBytes();
    await client.storage.from('pfp').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    return client.storage.from('pfp').getPublicUrl(path);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _succeeded = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = BotsService(Supabase.instance.client);
      // Save the row first (keeping the existing avatar in edit mode) so a
      // picture problem can't abort the save; upload the pfp afterwards.
      String? pfpUrl = _isEdit ? _existingPfpUrl : null;
      String botId;
      if (_isEdit) {
        botId = widget.botId!;
        await service.update(
          id: botId,
          name: _nameController.text.trim(),
          sysPrompt: _sysPromptController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          pfpUrl: pfpUrl,
        );
      } else {
        final bot = await service.create(
          name: _nameController.text.trim(),
          sysPrompt: _sysPromptController.text.trim(),
          bio: _bioController.text.trim().isEmpty
              ? null
              : _bioController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          pfpUrl: pfpUrl,
        );
        botId = bot.id;
      }
      if (_pickedPfp != null) {
        try {
          pfpUrl = await _uploadPfp(_pickedPfp!);
          await service.updatePfpUrl(botId, pfpUrl!);
        } catch (_) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
                'Picture upload failed — character saved without picture'),
          ));
        }
      }
      // Loading -> success morph before popping so the user sees the check.
      if (mounted) setState(() => _succeeded = true);
      await Future<void>.delayed(Motion.slow + const Duration(milliseconds: 250));
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _isEdit ? Icons.check_circle_outline_rounded : Icons.stars_rounded,
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.3, 0.3),
                    end: const Offset(1, 1),
                    duration: Motion.slow,
                    curve: Motion.springCurve,
                  )
                  .fade(duration: Motion.standard),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isEdit
                      ? 'Character updated'
                      : 'Character created! +10 credits',
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted) context.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit character' : 'Create character'),
      ),
      body: _loadingEdit
          ? const Center(child: CircularProgressIndicator())
          : _editFailed
              ? const PlaceholderView(
                  icon: Icons.error_outline_rounded,
                  label: 'Could not load this character',
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    children: [
                      Center(
                        child: PressableScale(
                          onTap: _pickPfp,
                          child: TweenAnimationBuilder<double>(
                            // Re-runs the ring pulse whenever the image changes.
                            key: ValueKey(_pickedPfp?.path ?? _existingPfpUrl),
                            tween: Tween(begin: 0, end: 1),
                            duration: Motion.slow,
                            curve: Motion.decelerateCurve,
                            builder: (context, t, child) {
                              final pulse = (1 - t);
                              return Stack(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.5 * pulse),
                                        width: 2 + 4 * pulse,
                                      ),
                                    ),
                                    child: child,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: CircleAvatar(
                                      radius: 15,
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      child: Icon(
                                        Icons.add_a_photo_rounded,
                                        size: 16,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                            child: _AvatarPreview(
                              pickedPath: _pickedPfp?.path,
                              url: _existingPfpUrl,
                              name: _nameController.text,
                            ),
                          ),
                        ),
                      )
                          .animate(delay: Motion.stagger(0))
                          .fade(duration: Motion.emphasized)
                          .slideY(
                            begin: 0.1,
                            end: 0,
                            duration: Motion.emphasized,
                            curve: Motion.decelerateCurve,
                          ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('bot-name-field'),
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          counterText: '',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Give your character a name'
                                : null,
                      )
                          .animate(delay: Motion.stagger(1))
                          .fade(duration: Motion.emphasized)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: Motion.emphasized,
                            curve: Motion.decelerateCurve,
                          ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bioController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          hintText: 'One-liner shown in Discover',
                          counterText: '',
                        ),
                      )
                          .animate(delay: Motion.stagger(2))
                          .fade(duration: Motion.emphasized)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: Motion.emphasized,
                            curve: Motion.decelerateCurve,
                          ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Full backstory shown on the profile',
                        ),
                      )
                          .animate(delay: Motion.stagger(3))
                          .fade(duration: Motion.emphasized)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: Motion.emphasized,
                            curve: Motion.decelerateCurve,
                          ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('bot-sys-prompt-field'),
                        controller: _sysPromptController,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'System prompt',
                          helperText:
                              'Hidden from users — shapes how the character behaves',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Describe how it should behave'
                                : null,
                      )
                          .animate(delay: Motion.stagger(4))
                          .fade(duration: Motion.emphasized)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: Motion.emphasized,
                            curve: Motion.decelerateCurve,
                          ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('bot-submit'),
                          onPressed: _submitting ? null : _submit,
                          child: AnimatedSwitcher(
                            duration: Motion.fast,
                            child: _submitting
                                ? (_succeeded
                                    ? const Icon(
                                        Icons.check_circle_outline_rounded,
                                        key: ValueKey('submit-success'),
                                      )
                                    : const SizedBox(
                                        key: ValueKey('submit-loading'),
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ))
                                : Text(
                                    key: const ValueKey('submit-label'),
                                    _isEdit ? 'Save changes' : 'Create character',
                                  ),
                          ),
                        ),
                      )
                          .animate(delay: Motion.stagger(5))
                          .fade(duration: Motion.emphasized)
                          .slideY(
                            begin: 0.08,
                            end: 0,
                            duration: Motion.emphasized,
                            curve: Motion.decelerateCurve,
                          ),
                    ],
                  ),
                ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({this.pickedPath, this.url, required this.name});

  final String? pickedPath;
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ImageProvider? foregroundImage = pickedPath != null
        ? FileImage(File(pickedPath!))
        : (url != null && url!.isNotEmpty ? NetworkImage(url!) : null);
    return CircleAvatar(
      radius: 48,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      foregroundImage: foregroundImage,
      onForegroundImageError: foregroundImage == null ? null : (_, __) {},
      child: Text(
        name.isEmpty ? '+' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
      ),
    );
  }
}
