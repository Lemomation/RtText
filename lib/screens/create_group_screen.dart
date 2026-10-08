import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/core/uuid.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/app_toast.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Screen to create a new group chat with humans and/or AI bots.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen>
    with SingleTickerProviderStateMixin {
  late final ConversationsService _conversationsService;
  late final BotsService _botsService;
  late final TabController _tabController;

  final _titleController = TextEditingController();
  final _searchController = TextEditingController();

  Uint8List? _avatarBytes;
  bool _isCreating = false;

  // Selected members
  final Map<String, Map<String, dynamic>> _selectedUsers = {};
  final Map<String, Bot> _selectedBots = {};

  // Search results
  List<Map<String, dynamic>> _userResults = [];
  List<Bot> _botResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _conversationsService = ConversationsService(client);
    _botsService = BotsService(client);
    _tabController = TabController(length: 2, vsync: this);

    _loadInitialCandidates();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialCandidates() async {
    setState(() => _searching = true);
    try {
      final bots = await _botsService.listExplore(limit: 30);
      final users = await _conversationsService.searchPeople('');
      if (mounted) {
        setState(() {
          _botResults = bots;
          _userResults = users;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _searching = true);
    try {
      if (_tabController.index == 0) {
        // Users
        final users = await _conversationsService.searchPeople(query);
        if (mounted) setState(() => _userResults = users);
      } else {
        // Bots
        final bots = await _botsService.search(query);
        if (mounted) setState(() => _botResults = bots);
      }
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() => _avatarBytes = bytes);
    }
  }

  Future<void> _createGroup() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showAppToast(context, 'Please enter a group name',
          style: AppToastStyle.error);
      return;
    }

    if (_selectedUsers.isEmpty && _selectedBots.isEmpty) {
      showAppToast(context, 'Please select at least one member or bot',
          style: AppToastStyle.error);
      return;
    }

    setState(() => _isCreating = true);

    try {
      String? avatarUrl;
      if (_avatarBytes != null) {
        final path = 'groups/${uuidV4()}.jpg';
        await Supabase.instance.client.storage.from('chat_media').uploadBinary(
              path,
              _avatarBytes!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        avatarUrl = Supabase.instance.client.storage
            .from('chat_media')
            .getPublicUrl(path);
      }

      final conv = await _conversationsService.createGroup(
        title: title,
        avatarUrl: avatarUrl,
        memberUserIds: _selectedUsers.keys.toList(),
        memberBotIds: _selectedBots.keys.toList(),
      );

      if (!mounted) return;
      showAppToast(context, 'Group created!', style: AppToastStyle.info);
      context.go('/chats');
      context.push('/chat/${conv.id}', extra: conv);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Failed to create group: $e',
          style: AppToastStyle.error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSelected = _selectedUsers.length + _selectedBots.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Create',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header: Avatar Picker & Group Name Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                PressableScale(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: _avatarBytes != null
                            ? MemoryImage(_avatarBytes!)
                            : null,
                        child: _avatarBytes == null
                            ? Icon(
                                Icons.group_rounded,
                                size: 32,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(
                            Icons.camera_alt_rounded,
                            size: 13,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    autofocus: true,
                    maxLength: 32,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'e.g. Sorcerer Squad',
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Selected Members Horizontal Chip List
          if (totalSelected > 0)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ..._selectedUsers.entries.map((e) {
                    final username = e.value['username'] as String? ?? 'User';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: BotAvatar(
                          name: username,
                          url: e.value['avatar_url'] as String?,
                          radius: 12,
                        ),
                        label: Text(username),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () {
                          setState(() => _selectedUsers.remove(e.key));
                        },
                      ),
                    );
                  }),
                  ..._selectedBots.entries.map((e) {
                    final bot = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: BotAvatar(
                          name: bot.name,
                          url: bot.pfpUrl,
                          radius: 12,
                        ),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(bot.name),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.2),
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
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () {
                          setState(() => _selectedBots.remove(e.key));
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

          const Divider(height: 1),

          // Search Input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search people or bots…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Tabs: Friends vs Bots
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'People'),
              Tab(text: 'AI Characters'),
            ],
            onTap: (_) => _onSearchChanged(_searchController.text),
          ),

          // Candidate List
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // 1. People Tab
                      _userResults.isEmpty
                          ? const Center(
                              child: Text('No matching people found'),
                            )
                          : ListView.builder(
                              itemCount: _userResults.length,
                              itemBuilder: (context, index) {
                                final user = _userResults[index];
                                final uid = user['id'] as String;
                                final username =
                                    user['username'] as String? ?? 'User';
                                final avatarUrl =
                                    user['avatar_url'] as String?;
                                final isSelected =
                                    _selectedUsers.containsKey(uid);

                                return CheckboxListTile(
                                  value: isSelected,
                                  secondary: BotAvatar(
                                    name: username,
                                    url: avatarUrl,
                                    radius: 20,
                                  ),
                                  title: Text(username),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedUsers[uid] = user;
                                      } else {
                                        _selectedUsers.remove(uid);
                                      }
                                    });
                                  },
                                );
                              },
                            ),

                      // 2. Bots Tab
                      _botResults.isEmpty
                          ? const Center(
                              child: Text('No matching bots found'),
                            )
                          : ListView.builder(
                              itemCount: _botResults.length,
                              itemBuilder: (context, index) {
                                final bot = _botResults[index];
                                final isSelected =
                                    _selectedBots.containsKey(bot.id);

                                return CheckboxListTile(
                                  value: isSelected,
                                  secondary: BotAvatar(
                                    name: bot.name,
                                    url: bot.pfpUrl,
                                    radius: 20,
                                  ),
                                  title: Row(
                                    children: [
                                      Text(bot.name),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
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
                                  ),
                                  subtitle: bot.bio != null
                                      ? Text(
                                          bot.bio!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedBots[bot.id] = bot;
                                      } else {
                                        _selectedBots.remove(bot.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
