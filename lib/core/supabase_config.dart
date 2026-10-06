/// Compile-time Supabase configuration passed via --dart-define.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static const String missingConfigMessage =
      'SUPABASE_URL and/or SUPABASE_ANON_KEY were not provided.\n'
      'Build with:\n'
      'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...';

  /// Deep-link redirect used for OAuth flows.
  static const oauthRedirectUrl =
      'io.supabase.flutterdeepauth://login-callback/';
}
