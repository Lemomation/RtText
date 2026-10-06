import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/app.dart';
import 'package:rttext/widgets/placeholder_view.dart';

void main() {
  testWidgets('shows configuration error UI when dart-defines are missing',
      (tester) async {
    // SUPABASE_URL / SUPABASE_ANON_KEY are not defined in the test
    // environment, mirroring the misconfigured-build path.
    await tester.pumpWidget(const RtTextApp.misconfigured());
    await tester.pumpAndSettle();

    expect(find.text('Configuration missing'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('placeholder view renders icon and label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlaceholderView(icon: Icons.forum_outlined, label: 'Hello'),
        ),
      ),
    );
    // One pump to let animations progress, then a settle-free assert.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
  });
}
