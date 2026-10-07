import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/services/updater_service.dart';
import 'package:rttext/widgets/update_prompt_dialog.dart';

void main() {
  testWidgets('renders update popup with Later and Update now buttons',
      (tester) async {
    const info = UpdateInfo(
      status: UpdateStatus.updateAvailable,
      installedVersion: '0.3.5',
      latestVersion: '0.3.6',
      downloadUrl: 'https://example.com/app.apk',
      apkSize: 15 * 1024 * 1024,
      notes: 'Bug fixes and performance improvements.',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdatePromptDialog(info: info),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('0.3.6'), findsOneWidget);
    expect(find.textContaining('15.0 MB'), findsOneWidget);
    expect(find.text('Bug fixes and performance improvements.'), findsOneWidget);
    expect(find.byKey(const Key('update-later-button')), findsOneWidget);
    expect(find.byKey(const Key('update-now-button')), findsOneWidget);
  });

  testWidgets('clicking Later closes the dialog', (tester) async {
    const info = UpdateInfo(
      status: UpdateStatus.updateAvailable,
      installedVersion: '0.3.5',
      latestVersion: '0.3.6',
      downloadUrl: 'https://example.com/app.apk',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdatePromptDialog(context, info),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-later-button')));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
  });
}
