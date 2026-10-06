import 'package:supabase_flutter/supabase_flutter.dart';

/// Bead balance access: the lazy daily claim and balance reads.
///
/// Balances only move server-side (signup grant, claim RPC, chat triggers,
/// ai-reply charge); there is deliberately no client-side write path.
class BeadsService {
  const BeadsService(this._client);

  final SupabaseClient _client;

  /// Current bead balance for the signed-in user.
  Future<int> balance() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 0;
    final row = await _client
        .from('profiles')
        .select('beads')
        .eq('id', uid)
        .maybeSingle();
    return ((row as Map<String, dynamic>?)?['beads'] as num?)?.toInt() ?? 0;
  }

  /// Claims the daily +20 beads. Returns the new balance, or null when the
  /// user already claimed today (or isn't signed in).
  Future<int?> claimDaily() async {
    if (_client.auth.currentUser == null) return null;
    final res = await _client.rpc('claim_daily_beads');
    final value = (res as num?)?.toInt();
    if (value == null || value < 0) return null;
    return value;
  }
}

/// Reply from the ai-reply edge function: the generated text plus the
/// caller's bead balance after the charge.
class AiReplyResult {
  const AiReplyResult({required this.content, this.remainingBeads});

  final String content;

  /// Null when the function didn't report a balance (older deploy).
  final int? remainingBeads;
}

/// Thrown by [ConversationsService.requestAiReply] when the edge function
/// answers 402 because the caller has no beads left.
class OutOfBeadsException implements Exception {
  const OutOfBeadsException();

  @override
  String toString() => 'Out of beads';
}
