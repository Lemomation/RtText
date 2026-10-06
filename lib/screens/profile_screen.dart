import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/widgets/placeholder_view.dart';

/// Signed-in user profile with sign-out (details in a later milestone).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(
            onPressed: () => auth.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: PlaceholderView(
        icon: Icons.person_outline_rounded,
        label: 'Signed in as ${auth.displayName ?? 'you'}',
      ),
    );
  }
}
