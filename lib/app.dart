import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:rttext/core/app_theme.dart';
import 'package:rttext/core/supabase_config.dart';
import 'package:rttext/providers/theme_provider.dart';

/// Root widget. [RtTextApp.misconfigured] renders a friendly error screen
/// instead of crashing when --dart-define values are missing.
class RtTextApp extends StatelessWidget {
  const RtTextApp({
    super.key,
    required this.router,
    required this.themeProvider,
  }) : misconfigured = false;

  const RtTextApp.misconfigured({super.key})
      : router = null,
        themeProvider = null,
        misconfigured = true;

  final GoRouter? router;
  final ThemeProvider? themeProvider;
  final bool misconfigured;

  @override
  Widget build(BuildContext context) {
    final provider = themeProvider;
    if (misconfigured || provider == null) {
      return MaterialApp(
        title: 'RtText',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const _MissingConfigScreen(),
      );
    }
    return ChangeNotifierProvider<ThemeProvider>.value(
      value: provider,
      child: AnimatedBuilder(
        animation: provider,
        builder: (context, _) => MaterialApp.router(
          title: 'RtText',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(seed: provider.seed),
          routerConfig: router,
        ),
      ),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 64),
              const SizedBox(height: 24),
              Text(
                'Configuration missing',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                SupabaseConfig.missingConfigMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
