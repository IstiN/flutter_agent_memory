import 'package:flutter_agent_memory/src/agents/kb_qa_mapping_agent.dart';
import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/models/analysis_result.dart';
import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/kb_context.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:test/test.dart';

class _FakeProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model, void Function()? onCancel}) async {
    return '''
MAPPING | answerId=n_1 | questionId=q_1 | confidence=0.9
MAPPING | answerId=a_1 | questionId=q_2 | confidence=0.7
''';
  }

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async => chat(messages.last.content);

  @override
  Stream<String> chatStream(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chat(prompt, model: model, onCancel: onCancel);
  }

  @override
  Stream<String> chatMessagesStream(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chatMessages(messages, model: model, onCancel: onCancel);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  test('maps answers and notes to existing unanswered questions', () async {
    final agent = KBQuestionAnswerMappingAgent(_FakeProvider());
    final result = await agent.mapAnswers(
      AnalysisResult(
        questions: [],
        answers: [
          Answer(
            id: 'a_1',
            author: 'A',
            text: 'Use provider.',
            date: '2024-01-01T00:00:00Z',
            area: 'dev',
            topics: const ['state'],
            tags: const [],
            quality: 1.0,
            links: const [],
          ),
        ],
        notes: [
          Note(
            id: 'n_1',
            author: 'B',
            text: 'Use Riverpod.',
            date: '2024-01-01T00:00:00Z',
            area: 'dev',
            topics: const ['state'],
            tags: const [],
            answersQuestions: const [],
            links: const [],
          ),
        ],
      ),
      KBContext(
        existingQuestions: [
          const QuestionSummary(id: 'q_1', author: 'X', text: 'State?', area: 'dev', answered: false),
          const QuestionSummary(id: 'q_2', author: 'Y', text: 'Provider?', area: 'dev', answered: false),
        ],
      ),
    );

    expect(result.mappings, hasLength(2));
    expect(result.mappings.first.questionId, 'q_1');
    expect(result.mappings.first.answerId, 'n_1');
    expect(result.mappings.first.confidence, closeTo(0.9, 0.001));
  });

  test('short-circuits when there are no new answers or notes', () async {
    final agent = KBQuestionAnswerMappingAgent(_FakeProvider());
    final result = await agent.mapAnswers(
      const AnalysisResult(questions: [], answers: [], notes: []),
      KBContext(
        existingQuestions: [
          const QuestionSummary(id: 'q_1', author: 'X', text: 'State?', area: 'dev', answered: false),
        ],
      ),
    );

    expect(result.mappings, isEmpty);
  });

  test('short-circuits when there are no unanswered questions', () async {
    final agent = KBQuestionAnswerMappingAgent(_FakeProvider());
    final result = await agent.mapAnswers(
      AnalysisResult(
        questions: [],
        answers: [
          Answer(
            id: 'a_1',
            author: 'A',
            text: 'Answer',
            date: '2024-01-01T00:00:00Z',
            area: 'dev',
            topics: const [],
            tags: const [],
            quality: 1.0,
            links: const [],
          ),
        ],
        notes: [],
      ),
      KBContext(existingQuestions: []),
    );

    expect(result.mappings, isEmpty);
  });
}
