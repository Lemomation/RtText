import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/services/conversations_service.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/placeholder_view.dart';
import 'package:rttext/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Discover tab: two panes behind a segmented switch. 'Characters' is the
/// original grid of public AI characters with client-side search (bots load
/// through [BotsService.listPublic], the `public_bots` view, which never
/// exposes `sys_prompt`); 'People' is live username search for starting free
/// human DMs. Bot card PFPs participate in hero transitions to the bot
/// profile screen.
enum _DiscoverTab { characters, people }

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.loadBots});

  /// Overridable loader for widget tests; defaults to the public view.
  final Future<List<Bot>> Function({int limit})? loadBots;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final Future<List<Bot>> Function({int limit}) _loadBots;
  late Future<List<Bot>> _future;
  String _query = '';

  _DiscoverTab _tab = _DiscoverTab.characters;

  // People search state. The conversations service is created lazily so the
  // Characters tab keeps working in widget tests without a Supabase client.
  ConversationsService? _conversations;
  final _peopleController = TextEditingController();
  Timer? _debounce;
  bool _searchingPeople = false;
  List<Map<String, dynamic>>? _peopleResults;
  String? _creatingDmFor;

  @override
  void initState() {
    super.initState();
    _loadBots = widget.loadBots ??
        (({int limit = 50}) =>
            BotsService(Supabase.instance.client).listPublic(limit: limit));
    _future = _loadBots();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _peopleController.dispose();
    super.dispose();
  }

  ConversationsService get _service =>
      _conversations ??= ConversationsService(Supabase.instance.client);

  void _refresh() => setState(() => _future = _loadBots());

  List<Bot> _filtered(List<Bot> bots) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return bots;
    return bots
        .where((b) =>
            b.name.toLowerCase().contains(q) ||
            (b.bio ?? '').toLowerCase().contains(q))
        .toList();
  }

  /// Debounced username lookup; an empty query resets back to the hint.
  void _onPeopleQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _searchingPeople = false;
        _peopleResults = null;
      });
      return;
    }
    // Rebuild so the clear button / hint state tracks the typed text.
    setState(() {});
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => _runPeopleSearch(q),
    );
  }

  Future<void> _runPeopleSearch(String q) async {
    setState(() => _searchingPeople = true);
    try {
      final results = await _service.searchPeople(q);
      // Ignore a stale response that lost the race against a newer query.
      if (!mounted || _peopleController.text.trim() != q) return;
      setState(() {
        _peopleResults = results;
        _searchingPeople = false;
      });
    } catch (_) {
      if (!mounted || _peopleController.text.trim() != q) return;
      setState(() {
        _peopleResults = const [];
        _searchingPeople = false;
      });
    }
  }

  /// Finds (or creates) the free 1:1 DM with [person] and opens it.
  Future<void> _openDm(Map<String, dynamic> person) async {
    final id = person['id'] as String?;
    if (id == null || _creatingDmFor != null) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creatingDmFor = id);
    try {
      final conv = await _service.getOrCreateDm(id);
      if (!mounted) return;
      setState(() => _creatingDmFor = null);
      await router.push('/chat/${conv.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _creatingDmFor = null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the chat')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create character',
            onPressed: () => context.push('/create-bot'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<_DiscoverTab>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _DiscoverTab.characters,
                  label: Text('Characters'),
                  icon: Icon(Icons.auto_awesome),
                ),
                ButtonSegment(
                  value: _DiscoverTab.people,
                  label: Text('People'),
                  icon: Icon(Icons.group_outline),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.standard,
              switchInCurve: Motion.decelerateCurve,
              switchOutCurve: Motion.emphasizedCurve,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _tab == _DiscoverTab.characters
                  ? KeyedSubtree(
                      key: const ValueKey(_DiscoverTab.characters),
                      child: _buildCharactersTab(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey(_DiscoverTab.people),
                      child: _buildPeopleTab(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ characters tab --

  /// The original bot gallery, unchanged apart from living behind the tab.
  Widget _buildCharactersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            key: const Key('discover-search'),
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search characters',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _query = ''),
                    ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Bot>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return PlaceholderView(
                  icon: Icons.cloud_off,
                  label: 'Could not load bots',
                  actionLabel: 'Retry',
                  onAction: _refresh,
                );
              }
              final bots = _filtered(snapshot.data ?? const []);
              if (bots.isEmpty) {
                return _query.trim().isEmpty
                    ? const _EmptyDiscover()
                    : PlaceholderView(
                        icon: Icons.search_off_rounded,
                        label: 'No characters match "$_query"',
                      );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  _refresh();
                  await _future.catchError((_) => const <Bot>[]);
                },
                child: GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: bots.length,
                  itemBuilder: (context, index) => _BotCard(
                    bot: bots[index],
                    index: index,
                    onTap: () => context.push('/bot/${bots[index].id}'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- people tab --

  Widget _buildPeopleTab() {
    final query = _peopleController.text.trim();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            key: const Key('people-search'),
            controller: _peopleController,
            onChanged: _onPeopleQueryChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              final q = value.trim();
              if (q.isNotEmpty) _runPeopleSearch(q);
            },
            decoration: InputDecoration(
              hintText: 'Search a username',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _peopleController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _debounce?.cancel();
                        _peopleController.clear();
                        setState(() {
                          _searchingPeople = false;
                          _peopleResults = null;
                        });
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: _buildPeopleResults(query),
        ),
      ],
    );
  }

  Widget _buildPeopleResults(String query) {
    if (query.isEmpty) {
      return const PlaceholderView(
        icon: Icons.person_search_rounded,
        label: 'Search a username to start chatting',
      );
    }
    if (_searchingPeople && _peopleResults == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _peopleResults;
    if (results == null || results.isEmpty) {
      return PlaceholderView(
        icon: Icons.search_off_rounded,
        label: _searchingPeople ? 'Searching…' : 'No people match "$query"',
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final person = results[index];
        final username = (person['username'] as String?) ?? '?';
        return ListTile(
          leading: BotAvatar(
            name: username,
            url: person['avatar_url'] as String?,
            radius: 22,
          ),
          title: Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _creatingDmFor == person['id']
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.6),
                ),
          onTap: () => _openDm(person),
        )
            .animate(delay: Motion.stagger(index, stepMs: 40))
            .fade(duration: Motion.emphasized)
            .slideX(
              begin: 0.05,
              end: 0,
              duration: Motion.emphasized,
              curve: Motion.decelerateCurve,
            );
      },
    );
  }
}

class _BotCard extends StatelessWidget {
  const _BotCard({required this.bot, required this.index, required this.onTap});

  final Bot bot;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'bot-pfp-${bot.id}',
                  child: BotAvatar(name: bot.name, url: bot.pfpUrl, radius: 36),
                ),
                const SizedBox(height: 10),
                Text(
                  bot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                if ((bot.bio ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    bot.bio!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    )
        .animate(delay: Motion.stagger(index, stepMs: 60))
        .fade(duration: Motion.emphasized)
        .slideY(
          begin: 0.08,
          end: 0,
          duration: Motion.emphasized,
          curve: Motion.decelerateCurve,
        );
  }
}

/// Animated empty state shown when the public gallery is empty.
class _EmptyDiscover extends StatelessWidget {
  const _EmptyDiscover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.explore_rounded,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No bots yet — be the first to create one!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          PressableScale(
            onTap: () => context.push('/create-bot'),
            child: FilledButton.icon(
              key: const Key('discover-create-cta'),
              onPressed: () => context.push('/create-bot'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Create a character'),
            ),
          ),
        ],
      )
          .animate()
          .fade(duration: Motion.slow)
          .scale(
            begin: const Offset(0.92, 0.92),
            end: const Offset(1, 1),
            duration: Motion.slow,
            curve: Motion.springCurve,
          )
          .blur(begin: const Offset(4, 4), end: Offset.zero, duration: Motion.slow),
    );
  }
}
