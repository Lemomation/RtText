import 'package:rttext/models/bot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bot CRUD. All reads go through the `public_bots` view, which omits
/// `sys_prompt`; the base `bots` table is only written to (and, via RLS,
/// only readable by its owner).
class BotsService {
  const BotsService(this._client);

  final SupabaseClient _client;

  static const _publicColumns = 'id,owner,name,bio,description,pfp_url,is_public,created_at';

  /// Public bots (plus the caller's own bots) for the Discover tab.
  Future<List<Bot>> listPublic({int limit = 50}) async {
    final rows = await _client
        .from('public_bots')
        .select(_publicColumns)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => Bot.fromMap(r as Map<String, dynamic>)).toList();
  }

  String? get _uid => _client.auth.currentUser?.id;

  /// Owner-only fetch straight from the `bots` table (RLS restricts reads to
  /// the owner), including `sys_prompt` — used to prefill the edit form.
  Future<Bot?> getOwnedById(String id) async {
    final row = await _client.from('bots').select().eq('id', id).maybeSingle();
    return row == null ? null : Bot.fromMap(row);
  }

  /// Bots the current user owns, for the profile screen's "My bots" list.
  Future<List<Bot>> listMine() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from('public_bots')
        .select(_publicColumns)
        .eq('owner', uid)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => Bot.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<Bot?> getById(String id) async {
    final row = await _client
        .from('public_bots')
        .select(_publicColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Bot.fromMap(row);
  }

  Future<Bot> create({
    required String name,
    required String sysPrompt,
    String? bio,
    String? description,
    String? pfpUrl,
    bool isPublic = true,
  }) async {
    final row = await _client.from('bots').insert({
      'owner': _uid,
      'name': name,
      'sys_prompt': sysPrompt,
      'bio': bio,
      'description': description,
      'pfp_url': pfpUrl,
      'is_public': isPublic,
    }).select(_publicColumns).single();
    return Bot.fromMap(row);
  }

  /// Owner-only patch of just `pfp_url` on an existing row — used after the
  /// bot is saved to attach the avatar uploaded post-save.
  Future<void> updatePfpUrl(String id, String url) =>
      _client.from('bots').update({'pfp_url': url}).eq('id', id);

  /// Owner-only update of a bot row. `pfpUrl` may be null to leave the
  /// current avatar untouched; pass it explicitly to change or clear it.
  Future<Bot> update({
    required String id,
    required String name,
    required String sysPrompt,
    String? bio,
    String? description,
    String? pfpUrl,
    bool isPublic = true,
  }) async {
    final row = await _client.from('bots').update({
      'name': name,
      'sys_prompt': sysPrompt,
      'bio': bio,
      'description': description,
      'pfp_url': pfpUrl,
      'is_public': isPublic,
    }).eq('id', id).select(_publicColumns).single();
    return Bot.fromMap(row);
  }

  Future<void> delete(String id) => _client.from('bots').delete().eq('id', id);
}
