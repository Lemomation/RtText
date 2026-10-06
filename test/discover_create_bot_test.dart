import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/screens/create_bot_screen.dart';
import 'package:rttext/screens/discover_screen.dart';

void main() {
  testWidgets('discover shows animated empty state when no bots exist',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverScreen(loadBots: ({int limit = 50}) async => const <Bot>[]),
        ),
      ),
    );
    // Let the future resolve and the entrance animations run.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.text('No bots yet — be the first to create one!'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    expect(find.text('Create a character'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('discover filters bots by name via the search bar',
      (tester) async {
    const bots = [
      Bot(id: 'b1', name: 'Aria', bio: 'A wise storyteller'),
      Bot(id: 'b2', name: 'Zed', bio: 'Blunt coding mentor'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiscoverScreen(loadBots: ({int limit = 50}) async => bots)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Aria'), findsOneWidget);
    expect(find.text('Zed'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('discover-search')), 'zed');
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Zed'), findsOneWidget);
    expect(find.text('Aria'), findsNothing);
  });

  testWidgets('create-bot form validates required fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CreateBotScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('System prompt'), findsOneWidget);

    // The form is taller than the test viewport (and ListView builds
    // children lazily), so drag until the submit button is materialized —
    // ensureVisible cannot see unbuilt children.
    await tester.scrollUntilVisible(
      find.byKey(const Key('bot-submit')),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bot-submit')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Give your character a name'), findsOneWidget);
    expect(find.text('Describe how it should behave'), findsOneWidget);
  });
}
