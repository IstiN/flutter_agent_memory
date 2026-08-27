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
    final buffer = StringBuffer()
      ..writeln(_frontmatter(_questionFrontmatter(q, source)))
      ..writeln('# Question: ${q.id}')
      ..writeln()
      ..writeln(q.text)
      ..writeln()
      ..writeln('**Asked by:** [[${normalizePersonName(q.author)}]]')
      ..writeln('**Date:** ${q.date}');

    _writeAreaTopics(buffer, q.area, q.topics);
    _writeLinks(buffer, q.links);
    _writeIdSection(buffer, '## Answers', answerIds);
    _writeIdSection(buffer, '## Related Notes', noteIds);

    return buffer.toString();
  }

  String renderAnswer(Answer a, String source) {
    final buffer = StringBuffer()
      ..writeln(_frontmatter(_answerFrontmatter(a, source)))
      ..writeln('# Answer: ${a.id}')
      ..writeln()
      ..writeln(a.text)
      ..writeln()
      ..writeln('**Provided by:** [[${normalizePersonName(a.author)}]]')
      ..writeln('**Date:** ${a.date}')
      ..writeln('**Quality Score:** ${a.quality.toStringAsFixed(2)}');

    _writeAreaTopics(buffer, a.area, a.topics);
    if (a.answersQuestion != null && a.answersQuestion!.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('**Answers:** [[${a.answersQuestion}]]');
    }
    _writeLinks(buffer, a.links);

    return buffer.toString();
  }

  String renderNote(Note n, String source) {
    final buffer = StringBuffer()
      ..writeln(_frontmatter(_noteFrontmatter(n, source)))
      ..writeln('# Note: ${n.id}')
      ..writeln()
      ..writeln(n.text)
      ..writeln()
      ..writeln('**By:** [[${normalizePersonName(n.author)}]]')
      ..writeln('**Date:** ${n.date}');

    _writeAreaTopics(buffer, n.area, n.topics);
    if (n.answersQuestions.isNotEmpty) {
      buffer.writeln();
      buffer.write('**Answers Questions:** ');
      buffer.writeln(n.answersQuestions.map((id) => '[[$id]]').join(', '));
    }
    _writeLinks(buffer, n.links);

    return buffer.toString();
  }

  Frontmatter _questionFrontmatter(Question q, String source) {
    final fm = _baseFrontmatter(q, 'question', source)
      ..['answered'] = q.answeredBy != null && q.answeredBy!.isNotEmpty;
    if (q.answeredBy != null && q.answeredBy!.isNotEmpty) {
      fm['answeredBy'] = q.answeredBy;
    }
    return fm..['tags'] = buildEntityTags(q.tags, source, '#question');
  }

  Frontmatter _answerFrontmatter(Answer a, String source) {
    final fm = _baseFrontmatter(a, 'answer', source)..['quality'] = a.quality;
    if (a.answersQuestion != null && a.answersQuestion!.isNotEmpty) {
      fm['answersQuestion'] = a.answersQuestion;
    }
    return fm..['tags'] = buildEntityTags(a.tags, source, '#answer');
  }

  Frontmatter _noteFrontmatter(Note n, String source) {
    final fm = _baseFrontmatter(n, 'note', source);
    _addNoteOptionalFields(fm, n);
    return fm..['tags'] = buildEntityTags(n.tags, source, '#note');
  }

  void _addNoteOptionalFields(Frontmatter fm, Note n) {
    _addNoteLinkFields(fm, n);
    _addNoteLevelAndRelations(fm, n);
  }

  void _addNoteLinkFields(Frontmatter fm, Note n) {
    if (n.answersQuestions.isNotEmpty) {
      fm['answersQuestions'] = n.answersQuestions;
    }
    _setStringIfNotEmpty(fm, 'memoryType', n.memoryType);
    _setStringIfNotEmpty(fm, 'validFrom', n.validFrom);
    _setStringIfNotEmpty(fm, 'validUntil', n.validUntil);
  }

  void _setStringIfNotEmpty(Frontmatter fm, String key, String? value) {
    if (value != null && value.isNotEmpty) fm[key] = value;
  }

  void _addNoteLevelAndRelations(Frontmatter fm, Note n) {
    if (n.level != MemoryLevel.raw) fm['level'] = n.level;
    if (n.relations.isNotEmpty) {
      fm['relations'] = n.relations
          .map((r) => r.toFrontmatterString())
          .toList();
    }
  }

  Frontmatter _baseFrontmatter(dynamic entity, String type, String source) {
    final fm = Frontmatter()
      ..['id'] = entity.id
      ..['type'] = type
      ..['title'] = entity.text
      ..['author'] = entity.author
      ..['date'] = entity.date
      ..['area'] = entity.area
      ..['topics'] = entity.topics
      ..['source'] = source
      ..['accessCount'] = entity.accessCount
      ..['importance'] = entity.importance;
    if (entity.lastAccessedAt != null && entity.lastAccessedAt!.isNotEmpty) {
      fm['lastAccessedAt'] = entity.lastAccessedAt;
    }
    return fm;
  }

  String _frontmatter(Frontmatter fm) => '---\n${fm.serialize()}---\n\n';

  void _writeAreaTopics(StringBuffer buffer, String area, List<String> topics) {
    if (area.isNotEmpty) {
      buffer.writeln('**Area:** [[${slugify(area)}|$area]]');
    }
    if (topics.isNotEmpty) {
      buffer.write('**Topics:** ');
      buffer.writeln(topics.map((t) => '[[${slugify(t)}|$t]]').join(', '));
    }
  }

  void _writeLinks(StringBuffer buffer, List<dynamic> links) {
    if (links.isEmpty) return;
    buffer.writeln();
    buffer.writeln('**Links:**');
    for (final link in links) {
      buffer.writeln('- [${link.title}](${link.url})');
    }
  }

  void _writeIdSection(StringBuffer buffer, String heading, List<String> ids) {
    if (ids.isEmpty) return;
    buffer.writeln();
    buffer.writeln(heading);
    buffer.writeln();
    for (final id in ids) buffer.writeln('![[$id]]\n');
  }

  List<String> buildEntityTags(
    List<String> originalTags,
    String source,
    String entityTag,
  ) {
    // `#`-prefixed tags are system tags (entity type, source scope). They are
    // always emitted exactly once and never duplicated across re-renders.
    final userTags = originalTags.where((t) => !t.startsWith('#')).toList();
    return [entityTag, _formatSourceTag(source), ...userTags];
  }

  String _formatSourceTag(String source) =>
      source.startsWith('source_') ? '#$source' : '#source_$source';
}
