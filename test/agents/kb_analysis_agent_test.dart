import 'package:flutter_agent_memory/src/agents/kb_analysis_agent.dart';
import 'package:flutter_agent_memory/src/models/kb_context.dart';
import 'package:test/test.dart';

import '../fake_llm_provider.dart';

void main() {
  final context = KBContext(
    maxQuestionId: 0,
    maxAnswerId: 0,
    maxNoteId: 0,
  );

  test('decodes line-oriented response', () async {
    final provider = FakeLlmProvider({
      'Analyze':
          'TYPE=Q | ID=q_1 | AUTHOR=Alice | DATE=2024-01-01T00:00:00Z | AREA=dev | TOPICS=dart | TAGS=dart | START=full | END=full',
    });
    final agent = KBAnalysisAgent(provider);
    final result = await agent.analyze('test', context);
    expect(result.questions, hasLength(1));
    expect(result.questions.first.author, 'Alice');
  });

  test('decodes JSON response as fallback', () async {
    final provider = FakeLlmProvider({
      'Analyze': '{"questions": [], "answers": [], "notes": []}',
    });
    final agent = KBAnalysisAgent(provider);
    final result = await agent.analyze('test', context);
    expect(result.questions, isEmpty);
  });

  test('recovers partial JSON when full decode fails', () async {
    final provider = FakeLlmProvider({
      'Analyze':
          '{"questions": [{"id":"q_1","author":"A","text":"t","date":"2024-01-01T00:00:00Z","area":"dev","topics":[],"tags":[]}], "answers": [broken, "notes": []}',
    });
    final agent = KBAnalysisAgent(provider);
    final result = await agent.analyze('test', context);
    expect(result.questions, hasLength(1));
  });

  test('throws when response cannot be parsed', () async {
    final provider = FakeLlmProvider({'Analyze': 'garbage'});
    final agent = KBAnalysisAgent(provider);
    expect(
      () => agent.analyze('test', context),
      throwsA(isA<FormatException>()),
    );
  });
}
