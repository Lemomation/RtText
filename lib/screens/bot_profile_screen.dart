import 'package:flutter/material.dart';
import 'package:rttext/widgets/placeholder_view.dart';

/// Public profile of an AI character (populated in a later milestone).
class BotProfileScreen extends StatelessWidget {
  const BotProfileScreen({super.key, required this.botId});

  final String botId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Character')),
      body: const PlaceholderView(
        icon: Icons.smart_toy_outlined,
        label: 'Character profile coming soon',
      ),
    );
  }
}
