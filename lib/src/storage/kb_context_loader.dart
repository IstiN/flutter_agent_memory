import 'dart:io';

import '../models/kb_context.dart';
import 'kb_file_parser.dart';

/// Loads existing knowledge-base state from disk.
class KBContextLoader {
  final KBFileParser _parser = KBFileParser();

  KBContext loadContext(Directory outputDir) {
    final context = KBContext();

    final questionsDir = Directory(_path(outputDir, 'questions'));
    final answersDir = Directory(_path(outputDir, 'answers'));
    final notesDir = Directory(_path(outputDir, 'notes'));

    _scanQuestions(questionsDir, context);
    _scanAnswers(answersDir, context);
    _scanNotes(notesDir, context);

    context.maxQuestionId = _findMaxId(outputDir, 'q', 'questions');
    context.maxAnswerId = _findMaxId(outputDir, 'a', 'answers');
    context.maxNoteId = _findMaxId(outputDir, 'n', 'notes');

    return context;
  }

  void initializeOutputDirectories(Directory outputDir, {bool clean = false}) {
    final dirs = [
      'questions',
      'answers',
      'notes',
      'topics',
      'areas',
      'people',
      'stats',
      'inbox/raw',
      'inbox/analyzed',
    ];
    for (final dir in dirs) {
      final d = Directory(_path(outputDir, dir));
      if (clean && d.existsSync()) {
        d.deleteSync(recursive: true);
      }
      d.createSync(recursive: true);
    }
  }

  void _scanQuestions(Directory dir, KBContext context) {
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
      try {
        final question = _parser.parseQuestion(file.readAsStringSync());
        context.existingPeople.add(question.author);
        context.existingTopics.addAll(question.topics);
        context.existingQuestions.add(QuestionSummary(
          id: question.id,
          author: question.author,
          text: question.text,
          area: question.area,
          answered: question.answeredBy != null && question.answeredBy!.isNotEmpty,
        ));
      } catch (_) {
        // Skip malformed files.
      }
    }
  }

  void _scanAnswers(Directory dir, KBContext context) {
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
      try {
        final answer = _parser.parseAnswer(file.readAsStringSync());
        context.existingPeople.add(answer.author);
        context.existingTopics.addAll(answer.topics);
      } catch (_) {}
    }
  }

  void _scanNotes(Directory dir, KBContext context) {
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
      try {
        final note = _parser.parseNote(file.readAsStringSync());
        context.existingPeople.add(note.author);
        context.existingTopics.addAll(note.topics);
      } catch (_) {}
    }
  }

  int _findMaxId(Directory outputDir, String prefix, String dirName) {
    final dir = Directory(_path(outputDir, dirName));
    if (!dir.existsSync()) return 0;
    var max = 0;
    final regex = RegExp('^${prefix}_(\\d+)\\.md\$');
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      final match = regex.firstMatch(name);
      if (match != null) {
        final id = int.parse(match.group(1)!);
        if (id > max) max = id;
      }
    }
    return max;
  }

  String _path(Directory base, String relative) =>
      base.uri.resolve(relative).toFilePath();
}
