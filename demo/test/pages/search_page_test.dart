import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/search_page.dart';
import 'package:demo/services/kb_service.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('SearchPage', () {
    late KbService kbService;

    setUp(() async {
      kbService = await createTestKbService();
      await kbService.store.addQuestion(
        text: 'How to test Flutter widgets?',
        area: 'testing',
        tags: ['flutter', 'testing'],
      );
      await kbService.store.addNote(
        text: 'Dart is great',
        area: 'dart',
        tags: ['dart'],
      );
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: SearchPage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('searches by tags and shows results', (tester) async {
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField).first, 'flutter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('How to test Flutter widgets?'), findsOneWidget);
      expect(find.text('Dart is great'), findsNothing);
    });

    testWidgets('shows LLM off message for text search without provider', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('By text'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'widgets');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('Configure provider'), findsOneWidget);
    });
  });
}
