import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/core/app_theme.dart';
import 'package:rttext/core/supabase_config.dart';

/// Root widget. [RtTextApp.misconfigured] renders a friendly error screen
/// instead of crashing when --dart-define values are missing.
class RtTextApp extends StatelessWidget {
  const RtTextApp({super.key, required this.router})
      : misconfigured = false;

  const RtTextApp.misconfigured({super.key})
      : router = null,
        misconfigured = true;

  final GoRouter? router;
  final bool misconfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RtText',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: misconfigured ? null : router,
      home: misconfigured ? const _MissingConfigScreen() : null,
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
