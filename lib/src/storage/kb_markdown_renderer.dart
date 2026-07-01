import '../models/answer.dart';
import '../models/memory_level.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../utils/frontmatter.dart';
import '../utils/slugify.dart';

/// Renders knowledge-base entities as Obsidian-compatible Markdown strings.
///
/// This is intentionally decoupled from I/O so that any [KbStorage] backend
/// can reuse the same Markdown representation.
class KbMarkdownRenderer {
  const KbMarkdownRenderer();

  String renderQuestion(
    Question q,
    String source, {
    List<String> answerIds = const [],
    List<String> noteIds = const [],
  }) {
    final fm = Frontmatter()
      ..['id'] = q.id
      ..['type'] = 'question'
      ..['title'] = q.text
      ..['author'] = q.author
      ..['date'] = q.date
      ..['area'] = q.area
      ..['topics'] = q.topics
      ..['answered'] = q.answeredBy != null && q.answeredBy!.isNotEmpty
      ..['source'] = source
      ..['accessCount'] = q.accessCount
      ..['importance'] = q.importance;
    if (q.answeredBy != null && q.answeredBy!.isNotEmpty)
      fm['answeredBy'] = q.answeredBy;
    if (q.lastAccessedAt != null && q.lastAccessedAt!.isNotEmpty)
      fm['lastAccessedAt'] = q.lastAccessedAt;

    fm['tags'] = buildEntityTags(q.tags, source, '#question');

    final buffer = StringBuffer()
      ..writeln('---')
      ..write(fm.serialize())
      ..writeln('---')
      ..writeln()
      ..writeln('# Question: ${q.id}')
      ..writeln()
      ..writeln(q.text)
      ..writeln()
      ..writeln('**Asked by:** [[${normalizePersonName(q.author)}]]')
      ..writeln('**Date:** ${q.date}');

    if (q.area.isNotEmpty) {
      buffer.writeln('**Area:** [[${slugify(q.area)}|${q.area}]]');
    }
    if (q.topics.isNotEmpty) {
      buffer.write('**Topics:** ');
      buffer.writeln(q.topics.map((t) => '[[${slugify(t)}|$t]]').join(', '));
    }
    if (q.links.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('**Links:**');
      for (final link in q.links) {
        buffer.writeln('- [${link.title}](${link.url})');
      }
    }
    if (answerIds.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## Answers');
      buffer.writeln();
      for (final id in answerIds) buffer.writeln('![[$id]]\n');
    }
    if (noteIds.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## Related Notes');
      buffer.writeln();
      for (final id in noteIds) buffer.writeln('![[$id]]\n');
    }

    return buffer.toString();
  }

  String renderAnswer(Answer a, String source) {
    final fm = Frontmatter()
      ..['id'] = a.id
      ..['type'] = 'answer'
      ..['title'] = a.text
      ..['author'] = a.author
      ..['date'] = a.date
      ..['area'] = a.area
      ..['topics'] = a.topics
      ..['quality'] = a.quality
      ..['source'] = source
      ..['accessCount'] = a.accessCount
      ..['importance'] = a.importance;
    if (a.answersQuestion != null && a.answersQuestion!.isNotEmpty)
      fm['answersQuestion'] = a.answersQuestion;
    if (a.lastAccessedAt != null && a.lastAccessedAt!.isNotEmpty)
      fm['lastAccessedAt'] = a.lastAccessedAt;

    fm['tags'] = buildEntityTags(a.tags, source, '#answer');

    final buffer = StringBuffer()
      ..writeln('---')
      ..write(fm.serialize())
      ..writeln('---')
      ..writeln()
      ..writeln('# Answer: ${a.id}')
      ..writeln()
      ..writeln(a.text)
      ..writeln()
      ..writeln('**Provided by:** [[${normalizePersonName(a.author)}]]')
      ..writeln('**Date:** ${a.date}')
      ..writeln('**Quality Score:** ${a.quality.toStringAsFixed(2)}');

    if (a.area.isNotEmpty) {
      buffer.writeln('**Area:** [[${slugify(a.area)}|${a.area}]]');
    }
    if (a.topics.isNotEmpty) {
      buffer.write('**Topics:** ');
      buffer.writeln(a.topics.map((t) => '[[${slugify(t)}|$t]]').join(', '));
    }
    if (a.answersQuestion != null && a.answersQuestion!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('**Answers:** [[${a.answersQuestion}]]');
    }
    if (a.links.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('**Links:**');
      for (final link in a.links) {
        buffer.writeln('- [${link.title}](${link.url})');
      }
    }

    return buffer.toString();
  }

  String renderNote(Note n, String source) {
    final fm = Frontmatter()
      ..['id'] = n.id
      ..['type'] = 'note'
      ..['title'] = n.text
      ..['author'] = n.author
      ..['date'] = n.date
      ..['area'] = n.area
      ..['topics'] = n.topics
      ..['source'] = source
      ..['accessCount'] = n.accessCount
      ..['importance'] = n.importance;
    if (n.answersQuestions.isNotEmpty)
      fm['answersQuestions'] = n.answersQuestions;
    if (n.lastAccessedAt != null && n.lastAccessedAt!.isNotEmpty)
      fm['lastAccessedAt'] = n.lastAccessedAt;
    if (n.memoryType != null && n.memoryType!.isNotEmpty)
      fm['memoryType'] = n.memoryType;
    if (n.validFrom != null && n.validFrom!.isNotEmpty)
      fm['validFrom'] = n.validFrom;
    if (n.validUntil != null && n.validUntil!.isNotEmpty)
      fm['validUntil'] = n.validUntil;
    if (n.level != MemoryLevel.raw) fm['level'] = n.level;
    if (n.relations.isNotEmpty) {
      fm['relations'] = n.relations
          .map((r) => r.toFrontmatterString())
          .toList();
    }

    fm['tags'] = buildEntityTags(n.tags, source, '#note');

    final buffer = StringBuffer()
      ..writeln('---')
      ..write(fm.serialize())
      ..writeln('---')
      ..writeln()
      ..writeln('# Note: ${n.id}')
      ..writeln()
      ..writeln(n.text)
      ..writeln()
      ..writeln('**By:** [[${normalizePersonName(n.author)}]]')
      ..writeln('**Date:** ${n.date}');

    if (n.area.isNotEmpty) {
      buffer.writeln('**Area:** [[${slugify(n.area)}|${n.area}]]');
    }
    if (n.topics.isNotEmpty) {
      buffer.write('**Topics:** ');
      buffer.writeln(n.topics.map((t) => '[[${slugify(t)}|$t]]').join(', '));
    }
    if (n.answersQuestions.isNotEmpty) {
      buffer.writeln();
      buffer.write('**Answers Questions:** ');
      buffer.writeln(n.answersQuestions.map((id) => '[[$id]]').join(', '));
    }
    if (n.links.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('**Links:**');
      for (final link in n.links) {
        buffer.writeln('- [${link.title}](${link.url})');
      }
    }

    return buffer.toString();
  }

  List<String> buildEntityTags(
    List<String> originalTags,
    String source,
    String entityTag,
  ) => <String>[
    if (!originalTags.any((t) => t == entityTag)) entityTag,
    if (!originalTags.any((t) => t.startsWith('#source_')))
      _formatSourceTag(source),
    ...originalTags.where((t) => t != entityTag && !t.startsWith('#source_')),
  ];

  String _formatSourceTag(String source) =>
      source.startsWith('source_') ? '#$source' : '#source_$source';
}
