import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/tags_page.dart';
import 'package:demo/services/kb_service.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('TagsPage', () {
    late KbService kbService;

    setUp(() async {
      kbService = await createTestKbService();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: TagsPage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows empty state', (tester) async {
      await pumpPage(tester);
      expect(find.text('No tags yet'), findsOneWidget);
    });

    testWidgets('groups records by tag', (tester) async {
      await kbService.store.addQuestion(text: 'Q1', tags: ['flutter', 'state']);
      await kbService.store.addAnswer(text: 'A1', tags: ['flutter']);
      await pumpPage(tester);

      expect(find.text('#flutter'), findsOneWidget);
      expect(find.text('2 records'), findsOneWidget);
      expect(find.text('#state'), findsOneWidget);
      expect(find.text('1 record'), findsWidgets);
    });

    testWidgets('opens record detail from tag card', (tester) async {
      await kbService.store.addQuestion(text: 'Q1', tags: ['flutter']);
      await pumpPage(tester);

      await tester.tap(find.text('Q1').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Q1'), findsWidgets);
    });
  });
}
