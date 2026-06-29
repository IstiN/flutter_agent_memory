import 'dart:io';

import '../models/analysis_result.dart';
import '../models/kb_context.dart';
import '../models/kb_result.dart';
import '../models/person_contributions.dart';
import '../utils/slugify.dart';
import 'kb_file_parser.dart';
import 'kb_id_mapper.dart';
import 'kb_statistics.dart';
import 'kb_structure_builder.dart';

/// High-level coordinator that writes the whole Markdown structure.
class KBStructureManager {
  final KBStructureBuilder _builder;
  final KBStatistics _statistics;
  final KBFileParser _parser;
  final KBIdMapper _idMapper;

  KBStructureManager()
      : _builder = KBStructureBuilder(),
        _statistics = KBStatistics(),
        _parser = KBFileParser(),
        _idMapper = KBIdMapper();

  KBResult buildResult(AnalysisResult analysisResult, Directory outputDir) {
    return KBResult(
      success: true,
      message: 'Build completed',
      questionsCount: analysisResult.questions.length,
      answersCount: analysisResult.answers.length,
      notesCount: analysisResult.notes.length,
      peopleCount: _countPeople(outputDir),
      topicsCount: _countTopics(outputDir),
      areasCount: _countAreas(outputDir),
    );
  }

  AnalysisResult mapIds(AnalysisResult analysis, KBContext context) =>
      _idMapper.mapAndUpdateIds(analysis, context);

  void buildStructure(
    AnalysisResult analysisResult,
    Directory outputDir,
    String sourceName,
    Map<String, PersonContributions> personContributions,
  ) {
    // Write Q/A/N files.
    for (final q in analysisResult.questions) {
      _builder.buildQuestionFile(q, outputDir, sourceName, analysisResult);
    }
    for (final a in analysisResult.answers) {
      _builder.buildAnswerFile(a, outputDir, sourceName);
    }
    for (final n in analysisResult.notes) {
      _builder.buildNoteFile(n, outputDir, sourceName);
    }

    // Recompute topic contributions from disk so multi-topic items are correct.
    _recalculateTopicContributions(personContributions, outputDir);

    // Write people profiles.
    final stats = _collectPersonStats(outputDir);
    for (final entry in personContributions.entries) {
      final personName = entry.key;
      final contributions = entry.value;
      final s = stats[personName] ?? _Counts();
      _builder.buildPersonProfile(personName, outputDir, sourceName, s.questions, s.answers, s.notes, contributions);
    }

    // Write area and topic files.
    _builder.buildAreaStructure(analysisResult, outputDir, sourceName);
    _builder.buildTopicFiles(analysisResult, outputDir, sourceName);
  }

  void rebuildPeopleProfiles(Directory outputDir, String sourceName) {
    final contributions = _collectPersonContributionsFromFiles(outputDir);
    final stats = _collectPersonStats(outputDir);
    for (final entry in contributions.entries) {
      final personName = entry.key;
      final s = stats[personName] ?? _Counts();
      _builder.buildPersonProfile(personName, outputDir, sourceName, s.questions, s.answers, s.notes, entry.value);
    }
  }

  void generateIndexes(Directory outputDir) {
    _builder.generatePeopleIndex(outputDir);
    _statistics.generateStatistics(outputDir);
  }

  Map<String, PersonContributions> collectPersonContributionsFromAnalysis(AnalysisResult analysis) {
    final result = <String, PersonContributions>{};

    for (final q in analysis.questions) {
      result.putIfAbsent(q.author, () => PersonContributions());
      for (final topic in q.topics) {
        result[q.author]!.questions.add(ContributionItem(id: q.id, topic: topic, date: q.date));
      }
    }
    for (final a in analysis.answers) {
      result.putIfAbsent(a.author, () => PersonContributions());
      for (final topic in a.topics) {
        result[a.author]!.answers.add(ContributionItem(id: a.id, topic: topic, date: a.date));
      }
    }
    for (final n in analysis.notes) {
      result.putIfAbsent(n.author, () => PersonContributions());
      for (final topic in n.topics) {
        result[n.author]!.notes.add(ContributionItem(id: n.id, topic: topic, date: n.date));
      }
    }
    return result;
  }

  Map<String, PersonContributions> _collectPersonContributionsFromFiles(Directory outputDir) {
    final result = <String, PersonContributions>{};

    void addContribution(String type, String author, String id, List<String> topics, String date) {
      result.putIfAbsent(author, () => PersonContributions());
      final contributions = result[author]!;
      for (final topic in topics) {
        final item = ContributionItem(id: id, topic: topic, date: date);
        switch (type) {
          case 'question':
            contributions.questions.add(item);
          case 'answer':
            contributions.answers.add(item);
          case 'note':
            contributions.notes.add(item);
        }
      }
    }

    final qDir = Directory('${outputDir.path}/questions');
    if (qDir.existsSync()) {
      for (final f in qDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final q = _parser.parseQuestion(f.readAsStringSync());
          addContribution('question', q.author, q.id, q.topics, q.date);
        } catch (_) {}
      }
    }

    final aDir = Directory('${outputDir.path}/answers');
    if (aDir.existsSync()) {
      for (final f in aDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final a = _parser.parseAnswer(f.readAsStringSync());
          addContribution('answer', a.author, a.id, a.topics, a.date);
        } catch (_) {}
      }
    }

    final nDir = Directory('${outputDir.path}/notes');
    if (nDir.existsSync()) {
      for (final f in nDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final n = _parser.parseNote(f.readAsStringSync());
          addContribution('note', n.author, n.id, n.topics, n.date);
        } catch (_) {}
      }
    }

    _recalculateTopicContributions(result, outputDir);
    return result;
  }

  void _recalculateTopicContributions(Map<String, PersonContributions> contributions, Directory outputDir) {
    final topicCounts = <String, Map<String, int>>{};

    void countFile(File file, String type) {
      try {
        late final String author;
        late final List<String> topics;
        switch (type) {
          case 'question':
            final q = _parser.parseQuestion(file.readAsStringSync());
            author = q.author;
            topics = q.topics;
          case 'answer':
            final a = _parser.parseAnswer(file.readAsStringSync());
            author = a.author;
            topics = a.topics;
          case 'note':
            final n = _parser.parseNote(file.readAsStringSync());
            author = n.author;
            topics = n.topics;
          default:
            return;
        }
        for (final topic in topics) {
          final topicId = slugify(topic);
          topicCounts.putIfAbsent(author, () => <String, int>{})[topicId] =
              (topicCounts[author]![topicId] ?? 0) + 1;
        }
      } catch (_) {}
    }

    final qDir = Directory('${outputDir.path}/questions');
    final aDir = Directory('${outputDir.path}/answers');
    final nDir = Directory('${outputDir.path}/notes');

    if (qDir.existsSync()) {
      for (final f in qDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) countFile(f, 'question');
    }
    if (aDir.existsSync()) {
      for (final f in aDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) countFile(f, 'answer');
    }
    if (nDir.existsSync()) {
      for (final f in nDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) countFile(f, 'note');
    }

    for (final entry in contributions.entries) {
      final person = entry.key;
      final topics = entry.value.topics;
      topics.clear();
      final counts = topicCounts[person] ?? {};
      for (final topicEntry in counts.entries) {
        topics.add(TopicContribution(topicId: topicEntry.key, count: topicEntry.value));
      }
    }
  }

  Map<String, _Counts> _collectPersonStats(Directory outputDir) {
    final stats = <String, _Counts>{};

    void increment(String author, void Function(_Counts c) fn) {
      fn(stats.putIfAbsent(author, () => _Counts()));
    }

    final qDir = Directory('${outputDir.path}/questions');
    if (qDir.existsSync()) {
      for (final f in qDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final q = _parser.parseQuestion(f.readAsStringSync());
          increment(q.author, (c) => c.questions++);
        } catch (_) {}
      }
    }

    final aDir = Directory('${outputDir.path}/answers');
    if (aDir.existsSync()) {
      for (final f in aDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final a = _parser.parseAnswer(f.readAsStringSync());
          increment(a.author, (c) => c.answers++);
        } catch (_) {}
      }
    }

    final nDir = Directory('${outputDir.path}/notes');
    if (nDir.existsSync()) {
      for (final f in nDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final n = _parser.parseNote(f.readAsStringSync());
          increment(n.author, (c) => c.notes++);
        } catch (_) {}
      }
    }

    return stats;
  }

  int _countPeople(Directory outputDir) {
    final dir = Directory('${outputDir.path}/people');
    return dir.existsSync() ? dir.listSync().whereType<Directory>().length : 0;
  }

  int _countTopics(Directory outputDir) {
    final dir = Directory('${outputDir.path}/topics');
    return dir.existsSync()
        ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md') && !f.path.endsWith('-desc.md')).length
        : 0;
  }

  int _countAreas(Directory outputDir) {
    final dir = Directory('${outputDir.path}/areas');
    return dir.existsSync() ? dir.listSync().whereType<Directory>().length : 0;
  }
}

class _Counts {
  int questions = 0;
  int answers = 0;
  int notes = 0;
}
