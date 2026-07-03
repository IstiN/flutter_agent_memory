import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/integration_tests_page.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('IntegrationTestsPage', () {
    testWidgets('shows configuration hint when no provider is set', (tester) async {
      final kbService = await createTestKbService();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: IntegrationTestsPage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Integration tests'), findsOneWidget);
      expect(find.textContaining('Configure a provider'), findsOneWidget);
      expect(find.textContaining('Run all'), findsNothing);
    });

    testWidgets('lists tests when a provider is configured', (tester) async {
      final settings = await createTestSettings({
        'provider': 'openai',
        'apiKey': 'test-key',
        'model': 'gpt-4o-mini',
      });
      final kbService = await createTestKbService(settings: settings);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: IntegrationTestsPage(kbService: kbService)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NeoCard), findsNWidgets(5));
      expect(find.text('Simple chat ping'), findsOneWidget);
      expect(find.text('JSON output'), findsOneWidget);
      expect(find.text('Tag generator'), findsOneWidget);
      expect(find.text('Raw text analysis'), findsOneWidget);
      expect(find.text('Search pipeline'), findsOneWidget);
      expect(find.widgetWithText(GlowButton, 'Run all'), findsOneWidget);
    });
  });
}
