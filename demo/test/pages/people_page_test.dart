import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/people_page.dart';
import 'package:demo/services/kb_service.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('PeoplePage', () {
    late KbService kbService;

    setUp(() async {
      kbService = await createTestKbService();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: PeoplePage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows empty state', (tester) async {
      await pumpPage(tester);
      expect(find.text('No people yet'), findsOneWidget);
    });

    testWidgets('groups records by author', (tester) async {
      await kbService.store.addQuestion(text: 'Q1', author: 'Alice', tags: ['x']);
      await kbService.store.addAnswer(text: 'A1', author: 'Alice', tags: ['x']);
      await pumpPage(tester);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('2 records'), findsOneWidget);
    });

    testWidgets('opens record detail from person card', (tester) async {
      await kbService.store.addQuestion(text: 'Q1', author: 'Bob', tags: ['x']);
      await pumpPage(tester);

      await tester.tap(find.text('Q1').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Q1'), findsWidgets);
    });
  });
}
