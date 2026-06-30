import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo/pages/graph_page.dart';
import 'package:demo/theme/app_theme.dart';

import '../test_helpers.dart';

void main() {
  group('GraphPage', () {
    testWidgets('renders markdown and diagram tabs', (tester) async {
      final kbService = await createTestKbService();
      await kbService.store.addQuestion(text: 'Q1');
      await kbService.store.addNote(text: 'N1');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: GraphPage(kbService: kbService)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Markdown'), findsOneWidget);
      expect(find.text('Diagram'), findsOneWidget);
      expect(find.text('Nodes'), findsOneWidget);
      expect(find.text('Edges'), findsOneWidget);
    });
  });
}
