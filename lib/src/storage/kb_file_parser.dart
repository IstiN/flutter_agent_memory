import '../models/answer.dart';
import '../models/link.dart';
import '../models/note.dart';
import '../models/question.dart';
import '../utils/frontmatter.dart';

/// Parses knowledge-base entities from Markdown files.
class KBFileParser {
  Question parseQuestion(String content) {
    final fm = parseFrontmatter(content);
    final body = extractBody(content);
    final text = _extractEntityText(body, 'Question');
    return Question(
      id: fm.getString('id') ?? '',
      author: fm.getString('author') ?? '',
      text: text,
      date: fm.getString('date') ?? '',
      area: fm.getString('area') ?? '',
      topics: fm.getStringList('topics'),
      tags: fm.getStringList('tags'),
      answeredBy: fm.getString('answeredBy'),
      links: _parseLinks(body),
      accessCount: fm.getString('accessCount') != null ? int.tryParse(fm.getString('accessCount')!) ?? 0 : 0,
      lastAccessedAt: fm.getString('lastAccessedAt'),
      importance: fm.getDouble('importance') ?? 0.5,
    );
  }

  Answer parseAnswer(String content) {
    final fm = parseFrontmatter(content);
    final body = extractBody(content);
    final text = _extractEntityText(body, 'Answer');
    return Answer(
      id: fm.getString('id') ?? '',
      author: fm.getString('author') ?? '',
      text: text,
      date: fm.getString('date') ?? '',
      area: fm.getString('area') ?? '',
      topics: fm.getStringList('topics'),
      tags: fm.getStringList('tags'),
      answersQuestion: fm.getString('answersQuestion'),
      quality: fm.getDouble('quality') ?? 0.0,
      links: _parseLinks(body),
      accessCount: fm.getString('accessCount') != null ? int.tryParse(fm.getString('accessCount')!) ?? 0 : 0,
      lastAccessedAt: fm.getString('lastAccessedAt'),
      importance: fm.getDouble('importance') ?? 0.5,
    );
  }

  Note parseNote(String content) {
    final fm = parseFrontmatter(content);
    final body = extractBody(content);
    final text = _extractEntityText(body, 'Note');
    return Note(
      id: fm.getString('id') ?? '',
      text: text,
      area: fm.getString('area') ?? '',
      topics: fm.getStringList('topics'),
      tags: fm.getStringList('tags'),
      author: fm.getString('author') ?? '',
      date: fm.getString('date') ?? '',
      answersQuestions: fm.getStringList('answersQuestions'),
      links: _parseLinks(body),
      accessCount: fm.getString('accessCount') != null ? int.tryParse(fm.getString('accessCount')!) ?? 0 : 0,
      lastAccessedAt: fm.getString('lastAccessedAt'),
      importance: fm.getDouble('importance') ?? 0.5,
    );
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
