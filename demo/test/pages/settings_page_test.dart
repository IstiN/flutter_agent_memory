import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/settings_page.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('SettingsPage', () {
    testWidgets('switches provider and updates status', (tester) async {
      final kbService = await createTestKbService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: SettingsPage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LLM ready'), findsOneWidget);
      expect(find.text('no'), findsOneWidget);

      await tester.tap(find.text('OpenAI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'OpenAI API key'), 'key');
      await tester.enterText(find.widgetWithText(TextField, 'Model'), 'gpt-4o-mini');
      await tester.dragUntilVisible(
        find.text('Save settings'),
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      await tester.tap(find.widgetWithText(GlowButton, 'Save settings'));
      await tester.pumpAndSettle();

      expect(find.text('yes'), findsOneWidget);
    });
  });
}
