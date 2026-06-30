import 'dart:io';

import '../utils/frontmatter.dart';
import '../utils/slugify.dart';

/// Generates index and overview files for the knowledge base.
class KBStatistics {
  void generateStatistics(Directory kbDir) {
    generateActivityTimeline(kbDir);
    generateTopicOverview(kbDir);
    generateIndex(kbDir);
  }

  void generateActivityTimeline(Directory kbDir) {
    final counts = _collectMonthlyCounts(kbDir);
    final file = File('${kbDir.path}/stats/activity_timeline.md');
    file.parent.createSync(recursive: true);

    final buffer = StringBuffer()
      ..writeln('# Activity Timeline')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln()
      ..writeln('| Month | Questions | Answers | Notes | Total |')
      ..writeln('|-------|-----------|---------|-------|-------|');

    final sortedMonths = counts.keys.toList()..sort();
    for (final month in sortedMonths) {
      final c = counts[month]!;
      final total = c.questions + c.answers + c.notes;
      buffer.writeln(
        '| $month | ${c.questions} | ${c.answers} | ${c.notes} | $total |',
      );
    }

    buffer
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_END -->');
    file.writeAsStringSync(buffer.toString());
  }

  void generateTopicOverview(Directory kbDir) {
    final stats = <_TopicStats>[];
    final topicsDir = Directory('${kbDir.path}/topics');
    if (topicsDir.existsSync()) {
      for (final file in topicsDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.md') && !f.path.endsWith('-desc.md'),
      )) {
        try {
          final fm = parseFrontmatter(file.readAsStringSync());
          final id = fm.getString('id') ?? '';
          final title = fm.getString('title') ?? id;
          stats.add(_TopicStats(id: id, name: title));
        } catch (_) {}
      }
    }

    final qDir = Directory('${kbDir.path}/questions');
    final aDir = Directory('${kbDir.path}/answers');
    final nDir = Directory('${kbDir.path}/notes');

    _countByTopic(qDir, stats, (s) => s.questions++);
    _countByTopic(aDir, stats, (s) => s.answers++);
    _countByTopic(nDir, stats, (s) => s.notes++);

    stats.sort((a, b) => b.total.compareTo(a.total));

    final file = File('${kbDir.path}/stats/topics_overview.md');
    file.parent.createSync(recursive: true);
    final buffer = StringBuffer()
      ..writeln('# Topics Overview')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln()
      ..writeln('| Topic | Questions | Answers | Notes | Total |')
      ..writeln('|-------|-----------|---------|-------|-------|');

    for (final s in stats) {
      buffer.writeln(
        '| [[${s.id}|${s.name}]] | ${s.questions} | ${s.answers} | ${s.notes} | ${s.total} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_END -->');
    file.writeAsStringSync(buffer.toString());
  }

  void generateIndex(Directory kbDir) {
    final qCount = _countFiles(Directory('${kbDir.path}/questions'));
    final aCount = _countFiles(Directory('${kbDir.path}/answers'));
    final nCount = _countFiles(Directory('${kbDir.path}/notes'));
    final peopleCount = Directory('${kbDir.path}/people').existsSync()
        ? Directory(
            '${kbDir.path}/people',
          ).listSync().whereType<Directory>().length
        : 0;
    final topicsCount = Directory('${kbDir.path}/topics').existsSync()
        ? Directory('${kbDir.path}/topics')
              .listSync()
              .whereType<File>()
              .where(
                (f) => f.path.endsWith('.md') && !f.path.endsWith('-desc.md'),
              )
              .length
        : 0;
    final areasCount = Directory('${kbDir.path}/areas').existsSync()
        ? Directory(
            '${kbDir.path}/areas',
          ).listSync().whereType<Directory>().length
        : 0;

    final file = File('${kbDir.path}/INDEX.md');
    final buffer = StringBuffer()
      ..writeln('# Knowledge Base Index')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln()
      ..writeln('## Overview')
      ..writeln()
      ..writeln('- **Questions:** $qCount')
      ..writeln('- **Answers:** $aCount')
      ..writeln('- **Notes:** $nCount')
      ..writeln('- **People:** $peopleCount')
      ..writeln('- **Topics:** $topicsCount')
      ..writeln('- **Areas:** $areasCount')
      ..writeln()
      ..writeln('## Navigation')
      ..writeln()
      ..writeln('- [[people/people|People]]')
      ..writeln('- [[stats/topics_overview|Topics Overview]]')
      ..writeln('- [[stats/activity_timeline|Activity Timeline]]')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_END -->');
    file.writeAsStringSync(buffer.toString());
  }

  Map<String, _MonthlyCounts> _collectMonthlyCounts(Directory kbDir) {
    final counts = <String, _MonthlyCounts>{};

    void scan(Directory dir, void Function(_MonthlyCounts c) increment) {
      if (!dir.existsSync()) return;
      for (final file in dir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.md'),
      )) {
        try {
          final fm = parseFrontmatter(file.readAsStringSync());
          final date = fm.getString('date');
          if (date == null || date.length < 7) continue;
          final month = date.substring(0, 7);
          increment(counts.putIfAbsent(month, () => _MonthlyCounts()));
        } catch (_) {}
      }
    }

    scan(Directory('${kbDir.path}/questions'), (c) => c.questions++);
    scan(Directory('${kbDir.path}/answers'), (c) => c.answers++);
    scan(Directory('${kbDir.path}/notes'), (c) => c.notes++);
    return counts;
  }

  void _countByTopic(
    Directory dir,
    List<_TopicStats> stats,
    void Function(_TopicStats s) increment,
  ) {
    if (!dir.existsSync()) return;
    for (final file in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.md'),
    )) {
      try {
        final topics = parseFrontmatter(
          file.readAsStringSync(),
        ).getStringList('topics');
        for (final topic in topics) {
          final topicId = slugify(topic);
          final stat = stats.firstWhere(
            (s) => s.id == topicId,
            orElse: () {
              final created = _TopicStats(id: topicId, name: topic);
              stats.add(created);
              return created;
            },
          );
          increment(stat);
        }
      } catch (_) {}
    }
  }

  int _countFiles(Directory dir) => dir.existsSync()
      ? dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))
            .length
      : 0;
}

class _MonthlyCounts {
  int questions = 0;
  int answers = 0;
  int notes = 0;
}

class _TopicStats {
  final String id;
  final String name;
  int questions = 0;
  int answers = 0;
  int notes = 0;

  _TopicStats({required this.id, required this.name});

  int get total => questions + answers + notes;
}
