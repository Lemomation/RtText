import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rttext/app.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/core/app_router.dart';
import 'package:rttext/core/supabase_config.dart';
import 'package:rttext/providers/theme_provider.dart';
import 'package:rttext/services/notifications_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    runApp(const RtTextApp.misconfigured());
    return;
  }

  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  await NotificationsService.initialize(Supabase.instance.client);

  final auth = AuthController(Supabase.instance.client)..start();
  final theme = ThemeProvider();
  await theme.load();

  runApp(
    ChangeNotifierProvider.value(
      value: auth,
      child: RtTextApp(router: AppRouter.build(auth), themeProvider: theme),
    ),
  );
}
