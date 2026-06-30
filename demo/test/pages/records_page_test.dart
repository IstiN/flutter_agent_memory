import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/records_page.dart';
import 'package:demo/services/kb_service.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('RecordsPage', () {
    late KbService kbService;

    setUp(() async {
      kbService = await createTestKbService();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: RecordsPage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows empty state', (tester) async {
      await pumpPage(tester);
      expect(find.text('Your knowledge base is empty'), findsOneWidget);
    });

    testWidgets('adds a question record', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Add first record'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'What is Flutter?');
      await tester.tap(find.widgetWithText(GlowButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('What is Flutter?'), findsOneWidget);
      expect(find.text('Your knowledge base is empty'), findsNothing);
    });

    testWidgets('deletes a record', (tester) async {
      await kbService.store.addQuestion(text: 'Q1');
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Q1'), findsNothing);
    });
  });
}
