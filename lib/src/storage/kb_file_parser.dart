import '../models/answer.dart';
import '../models/link.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../utils/frontmatter.dart';

/// Parses knowledge-base entities from Markdown files.
class KBFileParser {
  Question parseQuestion(String content) {
    final base = _parseBaseFields(content, 'Question');
    return Question(
      id: base.id,
      author: base.author,
      text: base.text,
      date: base.date,
      area: base.area,
      topics: base.topics,
      tags: base.tags,
      answeredBy: base.frontmatter.getString('answeredBy'),
      links: base.links,
      accessCount: base.accessCount,
      lastAccessedAt: base.lastAccessedAt,
      importance: base.importance,
    );
  }

  Answer parseAnswer(String content) {
    final base = _parseBaseFields(content, 'Answer');
    return Answer(
      id: base.id,
      author: base.author,
      text: base.text,
      date: base.date,
      area: base.area,
      topics: base.topics,
      tags: base.tags,
      answersQuestion: base.frontmatter.getString('answersQuestion'),
      quality: base.frontmatter.getDouble('quality') ?? 0.0,
      links: base.links,
      accessCount: base.accessCount,
      lastAccessedAt: base.lastAccessedAt,
      importance: base.importance,
    );
  }

  Note parseNote(String content) {
    final base = _parseBaseFields(content, 'Note');
    final memoryType = base.frontmatter.getString('memoryType');
    return Note(
      id: base.id,
      text: base.text,
      area: base.area,
      topics: base.topics,
      tags: base.tags,
      author: base.author,
      date: base.date,
      answersQuestions: base.frontmatter.getStringList('answersQuestions'),
      links: base.links,
      accessCount: base.accessCount,
      lastAccessedAt: base.lastAccessedAt,
      importance: base.importance,
      memoryType: memoryType,
      validFrom: base.frontmatter.getString('validFrom'),
      validUntil: base.frontmatter.getString('validUntil'),
    );
  }

  _BaseFields _parseBaseFields(String content, String entityType) {
    final fm = parseFrontmatter(content);
    final body = extractBody(content);
    final text = _extractEntityText(body, entityType);
    return _BaseFields(
      frontmatter: fm,
      id: fm.getString('id') ?? '',
      author: fm.getString('author') ?? '',
      text: text,
      date: fm.getString('date') ?? '',
      area: fm.getString('area') ?? '',
      topics: fm.getStringList('topics'),
      tags: fm.getStringList('tags'),
      links: _parseLinks(body),
      accessCount: _parseAccessCount(fm),
      lastAccessedAt: fm.getString('lastAccessedAt'),
      importance: fm.getDouble('importance') ?? 0.5,
    );
  }

  int _parseAccessCount(Frontmatter fm) {
    final raw = fm.getString('accessCount');
    return raw != null ? int.tryParse(raw) ?? 0 : 0;
  }

  String _extractEntityText(String body, String entityType) {
    // Body starts with "# Entity: id\n\n<text>\n\n**Asked by:** ..."
    final headingPattern = RegExp(r'^# \w+:\s*\S+\s*\n\n');
    final withoutHeading = body.replaceFirst(headingPattern, '');

    final separator = entityType == 'Question'
        ? '**Asked by:**'
        : entityType == 'Answer'
            ? '**Provided by:**'
            : '**By:**';

    final parts = withoutHeading.split('\n\n$separator');
    return parts.first.trim();
  }

  List<Link> _parseLinks(String body) {
    final links = <Link>[];
    final linksMatch = RegExp(r'\*\*Links:\*\*\s*\n(.+?)(?=\n\n|\*\*|\Z)', dotAll: true).firstMatch(body);
    if (linksMatch == null) return links;

    final linkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    for (final match in linkRegex.allMatches(linksMatch.group(1)!)) {
      links.add(Link(title: match.group(1)!, url: match.group(2)!));
    }
    return links;
  }
}

class _BaseFields {
  final Frontmatter frontmatter;
  final String id;
  final String author;
  final String text;
  final String date;
  final String area;
  final List<String> topics;
  final List<String> tags;
  final List<Link> links;
  final int accessCount;
  final String? lastAccessedAt;
  final double importance;

  _BaseFields({
    required this.frontmatter,
    required this.id,
    required this.author,
    required this.text,
    required this.date,
    required this.area,
    required this.topics,
    required this.tags,
    required this.links,
    required this.accessCount,
    required this.lastAccessedAt,
    required this.importance,
  });
}
