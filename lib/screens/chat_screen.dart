import 'package:flutter/material.dart';
import 'package:rttext/widgets/placeholder_view.dart';

/// One-to-one chat thread with an AI character (populated in a later
/// milestone with realtime messages).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.chatId});

  final String chatId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
      ),
      body: const PlaceholderView(
        icon: Icons.mark_chat_read_outlined,
        label: 'Messages coming soon',
      ),
    );
  }
}
