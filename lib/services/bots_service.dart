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
      'name': name,
      'sys_prompt': sysPrompt,
      'bio': bio,
      'description': description,
      'pfp_url': pfpUrl,
      'is_public': isPublic,
    }).select(_publicColumns).single();
    return Bot.fromMap(row);
  }

  Future<void> delete(String id) => _client.from('bots').delete().eq('id', id);
}
