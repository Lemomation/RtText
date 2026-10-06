import 'package:flutter/material.dart';
import 'package:rttext/widgets/placeholder_view.dart';

/// Character creation form (populated in a later milestone).
class CreateBotScreen extends StatelessWidget {
  const CreateBotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create character')),
      body: const PlaceholderView(
        icon: Icons.auto_awesome,
        label: 'Design your AI character here',
      ),
    );
  }
}
