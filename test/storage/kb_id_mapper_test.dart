import 'package:flutter_agent_memory/src/models/analysis_result.dart';
import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/kb_context.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/question.dart';
import 'package:flutter_agent_memory/src/storage/kb_id_mapper.dart';
import 'package:test/test.dart';

void main() {
  test('maps temporary ids to permanent ids and updates references', () {
    final analysis = AnalysisResult(
      questions: [
        Question(id: 'q_1', author: 'A', text: 'Q?', date: '2024-01-01', area: 'dev', topics: [], tags: [], answeredBy: 'a_1', links: []),
      ],
      answers: [
        Answer(id: 'a_1', author: 'B', text: 'A', date: '2024-01-01', area: 'dev', topics: [], tags: [], answersQuestion: 'q_1', quality: 0.8, links: []),
      ],
      notes: [
        Note(id: 'n_1', text: 'N', area: 'dev', topics: [], tags: [], author: 'C', date: '2024-01-01', answersQuestions: ['q_1'], links: []),
      ],
    );

    final context = KBContext(maxQuestionId: 5, maxAnswerId: 3, maxNoteId: 0);
    final mapper = KBIdMapper();
    final result = mapper.mapAndUpdateIds(analysis, context);

    expect(result.questions.first.id, 'q_0006');
    expect(result.answers.first.id, 'a_0004');
    expect(result.notes.first.id, 'n_0001');

    expect(result.questions.first.answeredBy, 'a_0004');
    expect(result.answers.first.answersQuestion, 'q_0006');
    expect(result.notes.first.answersQuestions, ['q_0006']);
  });
}
