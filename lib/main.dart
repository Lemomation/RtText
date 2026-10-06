import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rttext/app.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/core/app_router.dart';
import 'package:rttext/core/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    runApp(const RtTextApp.misconfigured());
    return;
  }

  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);

  final auth = AuthController(Supabase.instance.client)..start();

  runApp(
    ChangeNotifierProvider.value(
      value: auth,
      child: RtTextApp(router: AppRouter.build(auth)),
    ),
  );
}
