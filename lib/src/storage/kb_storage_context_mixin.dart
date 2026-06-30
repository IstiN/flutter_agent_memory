import 'dart:async';

import '../models/kb_context.dart';
import 'kb_file_parser.dart';

/// Shared context-scanning logic for [KbStorage] adapters.
///
/// Adapters that keep Markdown content locally (file, in-memory, SQLite, web)
/// can mix this in to get [loadContext] and max-id computation for free.
mixin KbStorageContextMixin {
  static const Map<String, String> _entityPrefix = {
    'question': 'q',
    'answer': 'a',
    'note': 'n',
  };

  KBFileParser get _parser => KBFileParser();

  FutureOr<List<String>> listEntityIds(String type);
  FutureOr<String?> readEntity(String type, String id);

  /// Scans stored questions, answers and notes to rebuild the KB context.
  Future<KBContext> loadContext() async {
    final context = KBContext();

    Future<void> scan(String type) async {
      for (final id in await listEntityIds(type)) {
        final content = await readEntity(type, id);
        if (content == null) continue;
        try {
          switch (type) {
            case 'question':
              final q = _parser.parseQuestion(content);
              context.existingPeople.add(q.author);
              context.existingTopics.addAll(q.topics);
              context.existingQuestions.add(
                QuestionSummary(
                  id: q.id,
                  author: q.author,
                  text: q.text,
                  area: q.area,
                  answered: q.answeredBy != null && q.answeredBy!.isNotEmpty,
                ),
              );
            case 'answer':
              final a = _parser.parseAnswer(content);
              context.existingPeople.add(a.author);
              context.existingTopics.addAll(a.topics);
            case 'note':
              final n = _parser.parseNote(content);
              context.existingPeople.add(n.author);
              context.existingTopics.addAll(n.topics);
          }
        } catch (_) {
          // Skip malformed records.
        }
      }
    }

    await scan('question');
    await scan('answer');
    await scan('note');

    context.maxQuestionId = await _findMaxId('question');
    context.maxAnswerId = await _findMaxId('answer');
    context.maxNoteId = await _findMaxId('note');

    return context;
  }

  Future<int> _findMaxId(String type) async {
    final prefix = _entityPrefix[type];
    if (prefix == null) return 0;
    final regex = RegExp('^${prefix}_(\\d+)\$');
    var max = 0;
    for (final id in await listEntityIds(type)) {
      final match = regex.firstMatch(id);
      if (match == null) continue;
      final value = int.parse(match.group(1)!);
      if (value > max) max = value;
    }
    return max;
  }
}
