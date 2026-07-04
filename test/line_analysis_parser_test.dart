import 'package:flutter_agent_memory/src/utils/line_analysis_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseLineAnalysisFormat', () {
    test('parses question and answer with full refs', () {
      const response = '''
TYPE=Q | ID=q_1 | AUTHOR=Alice | DATE=2024-11-15T09:00:00Z | AREA=development | TOPICS=dart-state-management | TAGS=dart;testing | ANSWERED_BY=a_1 | START=full | END=full
TYPE=A | ID=a_1 | AUTHOR=Bob | DATE=2024-11-15T09:01:00Z | AREA=development | TOPICS=dart-state-management | TAGS=riverpod | ANSWERS_QUESTION=q_1 | QUALITY=0.8 | START=full | END=full
''';
      final result = parseLineAnalysisFormat(response);
      expect(result.questions, hasLength(1));
      expect(result.answers, hasLength(1));
      expect(result.questions.first.id, 'q_1');
      expect(result.questions.first.author, 'Alice');
      expect(result.questions.first.startTextRef, 'full');
      expect(result.answers.first.answersQuestion, 'q_1');
      expect(result.answers.first.quality, 0.8);
    });

    test('parses note with specific refs', () {
      const response =
          'TYPE=N | ID=n_1 | AUTHOR=Lisa | DATE=2024-11-15T11:00:00Z | AREA=kubernetes | TOPICS=kubernetes-sidecars | TAGS=kubernetes-1.29 | MEMORY_TYPE=fact | START=Kubernetes 1.29 finally | END=init container hacks';
      final result = parseLineAnalysisFormat(response);
      expect(result.notes, hasLength(1));
      expect(result.notes.first.id, 'n_1');
      expect(result.notes.first.memoryType, 'fact');
      expect(result.notes.first.startTextRef, 'Kubernetes 1.29 finally');
    });

    test('ignores malformed lines and unknown types', () {
      const response = '''
TYPE=Q | ID=q_1 | AUTHOR=Alice | DATE=2024-11-15T09:00:00Z | AREA=development | TOPICS=dart | TAGS=dart | ANSWERED_BY=a_1 | START=full | END=full
BAD LINE
TYPE=Q | ID= | AUTHOR=Alice
TYPE=X | ID=x_1 | AUTHOR=Unknown
''';
      final result = parseLineAnalysisFormat(response);
      expect(result.questions, hasLength(1));
      expect(result.answers, isEmpty);
      expect(result.notes, isEmpty);
    });
  });

  group('recoverPartialLineAnalysis', () {
    test('recovers record lines surrounded by garbage', () {
      const response = '''
Some explanatory text before.
TYPE=Q | ID=q_1 | AUTHOR=Alice | DATE=2024-11-15T09:00:00Z | AREA=development | TOPICS=dart | TAGS=dart | ANSWERED_BY=a_1 | START=full | END=full
TYPE=A | ID=a_1 | AUTHOR=Bob | DATE=2024-11-15T09:01:00Z | AREA=development | TOPICS=dart | TAGS=riverpod | ANSWERS_QUESTION=q_1 | QUALITY=0.8 | START=full | END=full
```
''';
      final result = recoverPartialLineAnalysis(response);
      expect(result.questions, hasLength(1));
      expect(result.answers, hasLength(1));
    });
  });
}
