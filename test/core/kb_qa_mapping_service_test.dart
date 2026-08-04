import 'package:flutter_agent_memory/src/agents/kb_qa_mapping_agent.dart';
import 'package:flutter_agent_memory/src/core/kb_qa_mapping_service.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/models/analysis_result.dart';
import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/kb_context.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:test/test.dart';

class _StubProvider implements LlmProvider {
  final String response;
  _StubProvider(this.response);

  @override
  String get defaultModel => 'stub';

  @override
  Future<String> chat(String prompt, {String? model, void Function()? onCancel}) async => response;

  @override
  Future<String> chatMessages(messages, {String? model, void Function()? onCancel}) async => response;

  @override
  Stream<String> chatStream(String prompt, {String? model, void Function()? onCancel}) async* {
    yield response;
  }

  @override
  Stream<String> chatMessagesStream(messages, {String? model, void Function()? onCancel}) async* {
    yield response;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  test('short-circuits when all existing questions are answered', () async {
    final analysis = AnalysisResult(questions: [], answers: [], notes: []);
    final context = KBContext(
      existingQuestions: [
        const QuestionSummary(id: 'q_1', author: 'A', text: 'x', area: 'dev', answered: true),
      ],
    );

    final service = KBQAMappingService(KBQuestionAnswerMappingAgent(_StubProvider('')));
    await service.applyMapping(analysis, context);
    expect(analysis.answers, isEmpty);
  });

  test('links answer to existing question above confidence threshold', () async {
    final analysis = AnalysisResult(
      questions: [],
      answers: [
        Answer(
          id: 'a_1',
          author: 'B',
          text: 'Use Riverpod.',
          date: '2024-01-01T00:00:00Z',
          area: 'dev',
          topics: ['state'],
          tags: ['riverpod'],
          links: const [],
          quality: 0.9,
        ),
      ],
      notes: [],
    );
    final context = KBContext(
      existingQuestions: [
        const QuestionSummary(id: 'q_1', author: 'A', text: 'State?', area: 'dev', answered: false),
      ],
    );

    final response = 'MAPPING | ANSWERID=a_1 | QUESTIONID=q_1 | CONFIDENCE=0.9';
    final service = KBQAMappingService(KBQuestionAnswerMappingAgent(_StubProvider(response)));
    await service.applyMapping(analysis, context);

    expect(analysis.answers.first.answersQuestion, 'q_1');
  });

  test('links note to existing question above confidence threshold', () async {
    final analysis = AnalysisResult(
      questions: [],
      answers: [],
      notes: [
        Note(
          id: 'n_1',
          author: 'B',
          text: 'Use Riverpod.',
          date: '2024-01-01T00:00:00Z',
          area: 'dev',
          topics: ['state'],
          tags: ['riverpod'],
          answersQuestions: const [],
          links: const [],
        ),
      ],
    );
    final context = KBContext(
      existingQuestions: [
        const QuestionSummary(id: 'q_1', author: 'A', text: 'State?', area: 'dev', answered: false),
      ],
    );

    final response = 'MAPPING | ANSWERID=n_1 | QUESTIONID=q_1 | CONFIDENCE=0.9';
    final service = KBQAMappingService(KBQuestionAnswerMappingAgent(_StubProvider(response)));
    await service.applyMapping(analysis, context);

    expect(analysis.notes.first.answersQuestions, contains('q_1'));
  });

  test('ignores mappings below confidence threshold', () async {
    final analysis = AnalysisResult(
      questions: [],
      answers: [
        Answer(
          id: 'a_1',
          author: 'B',
          text: 'Maybe.',
          date: '2024-01-01T00:00:00Z',
          area: 'dev',
          topics: const [],
          tags: const [],
          links: const [],
          quality: 0.5,
        ),
      ],
      notes: [],
    );
    final context = KBContext(
      existingQuestions: [
        const QuestionSummary(id: 'q_1', author: 'A', text: 'x', area: 'dev', answered: false),
      ],
    );

    final response = 'MAPPING | ANSWERID=a_1 | QUESTIONID=q_1 | CONFIDENCE=0.5';
    final service = KBQAMappingService(KBQuestionAnswerMappingAgent(_StubProvider(response)));
    await service.applyMapping(analysis, context);

    expect(analysis.answers.first.answersQuestion, isNull);
  });
}
