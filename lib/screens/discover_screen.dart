import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/services/bots_service.dart';
import 'package:rttext/widgets/bot_avatar.dart';
import 'package:rttext/widgets/placeholder_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Discover tab: grid of public AI characters with client-side search.
/// Bots load through [BotsService.listPublic] (the `public_bots` view, which
/// never exposes `sys_prompt`). Card PFPs participate in hero transitions to
/// the bot profile screen.
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

  @override
  void initState() {
    super.initState();
    _loadBots = widget.loadBots ??
        (({int limit = 50}) =>
            BotsService(Supabase.instance.client).listPublic(limit: limit));
    _future = _loadBots();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create character',
            onPressed: () => context.go('/create-bot'),
          ),
        ],
      ),
      body: Column(
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
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BotCard extends StatelessWidget {
  const _BotCard({required this.bot, required this.index});

  final Bot bot;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/bot/${bot.id}'),
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
    )
        .animate(delay: (60 * (index % 12)).ms)
        .fade(duration: 350.ms)
        .slideY(
          begin: 0.08,
          end: 0,
          duration: 350.ms,
          curve: Curves.easeOut,
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
          FilledButton.icon(
            key: const Key('discover-create-cta'),
            onPressed: () => context.go('/create-bot'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Create a character'),
          ),
        ],
      )
          .animate()
          .fade(duration: 500.ms)
          .scale(
            begin: const Offset(0.92, 0.92),
            end: const Offset(1, 1),
            duration: 450.ms,
            curve: Curves.easeOutBack,
          )
          .blur(begin: const Offset(4, 4), end: Offset.zero, duration: 500.ms),
    );
  }
}
