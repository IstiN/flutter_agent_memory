import 'package:flutter_agent_memory/src/core/kb_analysis_validator.dart';
import 'package:flutter_agent_memory/src/models/analysis_result.dart';
import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/question.dart';
import 'package:test/test.dart';

Question _q({String author = 'A', String date = '2024-01-01', String area = 'a'}) =>
    Question(
      id: 'q_1',
      author: author,
      text: 't',
      date: date,
      area: area,
      topics: const [],
      tags: const [],
      links: const [],
    );

Answer _a({String author = 'A', String date = '2024-01-01', String area = 'a'}) =>
    Answer(
      id: 'a_1',
      author: author,
      text: 't',
      date: date,
      area: area,
      topics: const [],
      tags: const [],
      links: const [],
    );

Note _n({String author = 'A', String date = '2024-01-01', String area = 'a'}) =>
    Note(
      id: 'n_1',
      author: author,
      text: 't',
      date: date,
      area: area,
      topics: const [],
      tags: const [],
      links: const [],
      answersQuestions: const [],
    );

void main() {
  test('keeps complete entities', () {
    final analysis = AnalysisResult(
      questions: [_q()],
      answers: [_a()],
      notes: [_n()],
    );
    KBAnalysisValidator().validateAndClean(analysis);
    expect(analysis.questions, hasLength(1));
    expect(analysis.answers, hasLength(1));
    expect(analysis.notes, hasLength(1));
  });

  test('drops entities with empty author', () {
    final analysis = AnalysisResult(
      questions: [_q(author: '')],
      answers: [_a(author: '  ')],
      notes: [_n(author: '')],
    );
    KBAnalysisValidator().validateAndClean(analysis);
    expect(analysis.questions, isEmpty);
    expect(analysis.answers, isEmpty);
    expect(analysis.notes, isEmpty);
  });

  test('drops entities with empty date or area', () {
    final analysis = AnalysisResult(
      questions: [_q(date: '')],
      answers: [_a(area: '')],
      notes: [_n(date: '')],
    );
    KBAnalysisValidator().validateAndClean(analysis);
    expect(analysis.questions, isEmpty);
    expect(analysis.answers, isEmpty);
    expect(analysis.notes, isEmpty);
  });
}
