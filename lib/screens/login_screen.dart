import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/widgets/pressable_scale.dart';

/// Splash/login screen with an animated logo and Google OAuth button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _signingIn = false;

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      await context.read<AuthController>().signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.smart_toy_rounded, size: 88, color: theme.colorScheme.primary)
                  .animate()
                  .fade(duration: Motion.slow)
                  .scale(
                    begin: const Offset(0.6, 0.6),
                    end: const Offset(1, 1),
                    duration: Motion.slow,
                    curve: Motion.springCurve,
                  )
                  .blur(begin: const Offset(6, 6), end: Offset.zero, duration: Motion.slow),
              const SizedBox(height: 16),
              Text(
                'RtText',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ).animate().fade(delay: 200.ms, duration: Motion.slow),
              const SizedBox(height: 8),
              Text(
                'Chat with AI characters you create.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ).animate().fade(delay: 350.ms, duration: Motion.slow),
              const Spacer(),
              _GoogleButton(onPressed: _signingIn ? null : _signIn),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: onPressed == null
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.login_rounded),
        label: const Text('Continue with Google'),
      ),
    )
        .animate()
        .fade(delay: 500.ms, duration: Motion.slow)
        .slideY(
          begin: 0.2,
          end: 0,
          duration: Motion.slow,
          curve: Motion.emphasizedCurve,
        );
  }
}
