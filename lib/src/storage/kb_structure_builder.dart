import 'dart:collection';
import 'dart:io';

import '../models/analysis_result.dart';
import '../models/answer.dart';
import '../models/memory_level.dart';
import '../models/note.dart';
import '../models/person_contributions.dart';
import '../models/question.dart';
import '../utils/date_utils.dart';
import '../utils/frontmatter.dart';
import '../utils/slugify.dart';

/// Writes the Obsidian-compatible Markdown knowledge-base structure.
class KBStructureBuilder {
  void buildAreaStructure(AnalysisResult analysis, Directory outputDir, String sourceName) {
    final areaContributors = <String, Set<String>>{};
    final areaTopics = <String, Set<String>>{};
    final areasFromCurrentAnalysis = <String>{};

    void collectFromEntity(String? area, List<String>? topics, String? author) {
      if (area == null || area.isEmpty) return;
      areasFromCurrentAnalysis.add(area);
      areaContributors.putIfAbsent(area, () => <String>{});
      if (author != null && author.isNotEmpty) areaContributors[area]!.add(author);
      if (topics != null && topics.isNotEmpty) {
        areaTopics.putIfAbsent(area, () => <String>{})..addAll(topics);
      }
    }

    for (final q in analysis.questions) {
      collectFromEntity(q.area, q.topics, q.author);
    }
    for (final a in analysis.answers) {
      collectFromEntity(a.area, a.topics, a.author);
    }
    for (final n in analysis.notes) {
      collectFromEntity(n.area, n.topics, n.author);
    }

    final areasDir = Directory('${_path(outputDir)}/areas');
    if (areasDir.existsSync()) {
      for (final areaDir in areasDir.listSync().whereType<Directory>()) {
        final areaId = areaDir.uri.pathSegments.reversed.firstWhere((s) => s.isNotEmpty, orElse: () => '');
        final areaFile = File('${areaDir.path}/$areaId.md');
        if (!areaFile.existsSync()) continue;
        try {
          final content = areaFile.readAsStringSync();
          final title = parseFrontmatter(content).getString('title');
          if (title == null || title.isEmpty) continue;

          final contributors = parseFrontmatter(content).getStringList('contributors');
          if (contributors.isNotEmpty) {
            areaContributors.putIfAbsent(title, () => <String>{})..addAll(contributors);
          }

          final topicsSection = RegExp(r'##\s+Topics\s+(.+?)(?=##|<!--|\Z)', dotAll: true).firstMatch(content);
          if (topicsSection != null) {
            final linkRegex = RegExp(r'\[\[([^|\]]+)\|([^\]]+)\]\]');
            for (final m in linkRegex.allMatches(topicsSection.group(1)!)) {
              areaTopics.putIfAbsent(title, () => <String>{})..add(m.group(2)!.trim());
            }
          }
        } catch (_) {}
      }
    }

    areasDir.createSync(recursive: true);
    for (final area in areaContributors.keys) {
      final areaId = slugify(area);
      final areaDir = Directory('${areasDir.path}/$areaId')..createSync(recursive: true);
      final areaFile = File('${areaDir.path}/$areaId.md');
      final areaDescFile = File('${areaDir.path}/$areaId-desc.md');
      final sourceToAdd = areasFromCurrentAnalysis.contains(area) ? sourceName : null;
      _createAreaFileWithTopics(
        areaFile,
        areaDescFile,
        area,
        areaId,
        sourceToAdd,
        areaContributors[area]!.toList(),
        areaTopics[area]?.toList() ?? [],
      );
    }
  }

  void buildTopicFiles(AnalysisResult analysis, Directory outputDir, String sourceName) {
    final topicDataMap = <String, _TopicData>{};
    final topicsFromCurrentAnalysis = <String>{};

    void collectFromEntity(String type, String? id, List<String>? topics, String? author,
        List<String>? tags, String? answeredBy, String? answersQuestion) {
      if (id == null || topics == null) return;
      for (final topic in topics) {
        topicsFromCurrentAnalysis.add(topic);
        final data = topicDataMap.putIfAbsent(topic, () => _TopicData());
        switch (type) {
          case 'question':
            _recordQuestionLink(data, id, answeredBy);
          case 'answer':
            _recordAnswerLink(data, id, answersQuestion);
          case 'note':
            data.notes.add(id);
        }
        if (author != null && author.isNotEmpty) data.contributors.add(author);
        if (tags != null) data.tags.addAll(tags.where((t) => !t.startsWith('#')));
      }
    }

    for (final q in analysis.questions) {
      collectFromEntity('question', q.id, q.topics, q.author, q.tags, q.answeredBy, null);
    }
    for (final a in analysis.answers) {
      collectFromEntity('answer', a.id, a.topics, a.author, a.tags, null, a.answersQuestion);
    }
    for (final n in analysis.notes) {
      collectFromEntity('note', n.id, n.topics, n.author, n.tags, null, null);
    }

    _collectFromExistingFiles(outputDir, topicDataMap);

    final topicsDir = Directory('${_path(outputDir)}/topics')..createSync(recursive: true);
    for (final entry in topicDataMap.entries) {
      final topic = entry.key;
      final topicId = slugify(topic);
      final topicFile = File('${topicsDir.path}/$topicId.md');
      final topicDescFile = File('${topicsDir.path}/$topicId-desc.md');
      final sourceToAdd = topicsFromCurrentAnalysis.contains(topic) ? sourceName : null;
      _createTopicFileWithAggregation(topicFile, topicDescFile, topic, topicId, sourceToAdd, entry.value, analysis);
    }
  }

  void _collectFromExistingFiles(Directory outputDir, Map<String, _TopicData> topicDataMap) {
    void scan(String type, String dirName) {
      final dir = Directory('${_path(outputDir)}/$dirName');
      if (!dir.existsSync()) return;
      for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final content = file.readAsStringSync();
          final fm = parseFrontmatter(content);
          final id = fm.getString('id')?.replaceAll('"', '').trim();
          final author = fm.getString('author')?.replaceAll('"', '').trim();
          final topics = fm.getStringList('topics');
          if (id == null || topics.isEmpty) continue;
          for (final topic in topics) {
            if (topic.isEmpty) continue;
            final data = topicDataMap.putIfAbsent(topic, () => _TopicData());
            switch (type) {
              case 'question':
                final answeredBy = fm.getString('answeredBy')?.replaceAll('"', '').trim();
                _recordQuestionLink(data, id, answeredBy);
              case 'answer':
                final answersQuestion = fm.getString('answersQuestion')?.replaceAll('"', '').trim();
                _recordAnswerLink(data, id, answersQuestion);
              case 'note':
                data.notes.add(id);
            }
            if (author != null && author.isNotEmpty) data.contributors.add(author);
          }
        } catch (_) {}
      }
    }

    scan('question', 'questions');
    scan('answer', 'answers');
    scan('note', 'notes');
  }

  void buildQuestionFile(Question question, Directory outputDir, String sourceName, AnalysisResult analysisResult) {
    if (question.area.isEmpty) return;

    final answerIds = <String>[];
    final noteIds = <String>[];
    for (final a in analysisResult.answers) {
      if (a.answersQuestion == question.id) answerIds.add(a.id);
    }
    for (final n in analysisResult.notes) {
      if (n.answersQuestions.contains(question.id)) noteIds.add(n.id);
    }

    final dir = Directory('${_path(outputDir)}/questions')..createSync(recursive: true);
    final file = File('${dir.path}/${question.id}.md');
    file.writeAsStringSync(_renderQuestion(question, sourceName, answerIds, noteIds));
  }

  void buildAnswerFile(Answer answer, Directory outputDir, String sourceName) {
    if (answer.area.isEmpty) return;
    final dir = Directory('${_path(outputDir)}/answers')..createSync(recursive: true);
    final file = File('${dir.path}/${answer.id}.md');
    file.writeAsStringSync(_renderAnswer(answer, sourceName));
  }

  void buildNoteFile(Note note, Directory outputDir, String sourceName) {
    if (note.area.isEmpty) return;
    final dir = Directory('${_path(outputDir)}/notes')..createSync(recursive: true);
    final file = File('${dir.path}/${note.id}.md');
    file.writeAsStringSync(_renderNote(note, sourceName));
  }

  void buildPersonProfile(
    String personName,
    Directory outputDir,
    String sourceName,
    int questionsCount,
    int answersCount,
    int notesCount,
    PersonContributions contributions,
  ) {
    final personId = personFileId(personName);
    final dir = Directory('${_path(outputDir)}/people/$personId')..createSync(recursive: true);
    final file = File('${dir.path}/$personId.md');
    if (file.existsSync()) {
      _updatePersonFile(file, sourceName, questionsCount, answersCount, notesCount, contributions);
    } else {
      _createPersonFile(file, personName, personId, sourceName, questionsCount, answersCount, notesCount, contributions);
    }
  }

  void generatePeopleIndex(Directory outputDir) {
    final peopleDir = Directory('${_path(outputDir)}/people');
    if (!peopleDir.existsSync()) return;

    final people = peopleDir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.uri.pathSegments.reversed.firstWhere((s) => s.isNotEmpty, orElse: () => ''))
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();

    final buffer = StringBuffer()
      ..writeln('# People')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln()
      ..writeln('**Total contributors:** ${people.length}')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_END -->')
      ..writeln()
      ..writeln('## All Contributors')
      ..writeln();

    for (final personId in people) {
      buffer.writeln('![[$personId/$personId]]');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    var content = buffer.toString();
    if (people.isNotEmpty) {
      final lastSeparator = content.lastIndexOf('---\n\n');
      if (lastSeparator > 0) content = content.substring(0, lastSeparator);
    }

    File('${peopleDir.path}/people.md').writeAsStringSync(content);
  }

  void updateTopicWithStats(
    Directory outputDir,
    String topicId,
    int questionsCount,
    int answersCount,
    int notesCount,
    List<String> contributors,
  ) {
    final file = File('${_path(outputDir)}/topics/$topicId/$topicId.md');
    if (!file.existsSync()) return;
    var content = file.readAsStringSync();

    final buffer = StringBuffer()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln()
      ..writeln('## Recent Activity')
      ..writeln('- Questions: $questionsCount')
      ..writeln('- Answers: $answersCount')
      ..writeln('- Notes: $notesCount')
      ..writeln();

    if (contributors.isNotEmpty) {
      buffer.writeln('## Key Contributors');
      buffer.writeln();
      for (final c in contributors.toList()..sort()) {
        buffer.writeln('- [[${normalizePersonName(c)}|$c]]');
      }
      buffer.writeln();
    }

    buffer.write('<!-- AUTO_GENERATED_END -->');

    content = content.replaceAllMapped(
      RegExp(r'<!-- AUTO_GENERATED_START -->.*?<!-- AUTO_GENERATED_END -->', dotAll: true),
      (_) => buffer.toString(),
    );
    file.writeAsStringSync(content);
  }

  String _renderQuestion(Question q, String source, List<String> answerIds, List<String> noteIds) {
    final fm = Frontmatter()
      ..['id'] = q.id
      ..['type'] = 'question'
      ..['author'] = q.author
      ..['date'] = q.date
      ..['area'] = q.area
      ..['topics'] = q.topics
      ..['answered'] = q.answeredBy != null && q.answeredBy!.isNotEmpty
      ..['source'] = source
      ..['accessCount'] = q.accessCount
      ..['importance'] = q.importance;
    if (q.answeredBy != null && q.answeredBy!.isNotEmpty) fm['answeredBy'] = q.answeredBy;
    if (q.lastAccessedAt != null && q.lastAccessedAt!.isNotEmpty) fm['lastAccessedAt'] = q.lastAccessedAt;

    fm['tags'] = _buildEntityTags(q.tags, source, '#question');

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

  String _renderAnswer(Answer a, String source) {
    final fm = Frontmatter()
      ..['id'] = a.id
      ..['type'] = 'answer'
      ..['author'] = a.author
      ..['date'] = a.date
      ..['area'] = a.area
      ..['topics'] = a.topics
      ..['quality'] = a.quality
      ..['source'] = source
      ..['accessCount'] = a.accessCount
      ..['importance'] = a.importance;
    if (a.answersQuestion != null && a.answersQuestion!.isNotEmpty) fm['answersQuestion'] = a.answersQuestion;
    if (a.lastAccessedAt != null && a.lastAccessedAt!.isNotEmpty) fm['lastAccessedAt'] = a.lastAccessedAt;

    fm['tags'] = _buildEntityTags(a.tags, source, '#answer');

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

  String _renderNote(Note n, String source) {
    final fm = Frontmatter()
      ..['id'] = n.id
      ..['type'] = 'note'
      ..['author'] = n.author
      ..['date'] = n.date
      ..['area'] = n.area
      ..['topics'] = n.topics
      ..['source'] = source
      ..['accessCount'] = n.accessCount
      ..['importance'] = n.importance;
    if (n.answersQuestions.isNotEmpty) fm['answersQuestions'] = n.answersQuestions;
    if (n.lastAccessedAt != null && n.lastAccessedAt!.isNotEmpty) fm['lastAccessedAt'] = n.lastAccessedAt;
    if (n.memoryType != null && n.memoryType!.isNotEmpty) fm['memoryType'] = n.memoryType;
    if (n.validFrom != null && n.validFrom!.isNotEmpty) fm['validFrom'] = n.validFrom;
    if (n.validUntil != null && n.validUntil!.isNotEmpty) fm['validUntil'] = n.validUntil;
    if (n.level != MemoryLevel.raw) fm['level'] = n.level;
    if (n.relations.isNotEmpty) {
      fm['relations'] = n.relations.map((r) => r.toFrontmatterString()).toList();
    }

    fm['tags'] = _buildEntityTags(n.tags, source, '#note');

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

  void _createPersonFile(
    File file,
    String name,
    String id,
    String source,
    int questions,
    int answers,
    int notes,
    PersonContributions contributions,
  ) {
    final fm = Frontmatter()
      ..['id'] = id
      ..['name'] = name
      ..['type'] = 'person'
      ..['sources'] = [source]
      ..['questionsAsked'] = questions
      ..['answersProvided'] = answers
      ..['notesContributed'] = notes
      ..['tags'] = ['#person', _formatSourceTag(source)];

    final buffer = StringBuffer()
      ..writeln('---')
      ..write(fm.serialize())
      ..writeln('---')
      ..writeln()
      ..writeln('# $name')
      ..writeln()
      ..writeln('![[$id-desc]]')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln();

    _appendContributions(buffer, contributions);

    buffer.writeln('<!-- AUTO_GENERATED_END -->');
    file.writeAsStringSync(buffer.toString());
  }

  void _updatePersonFile(
    File file,
    String newSource,
    int questions,
    int answers,
    int notes,
    PersonContributions contributions,
  ) {
    var content = file.readAsStringSync();
    final fm = parseFrontmatter(content);
    final sources = fm.getStringList('sources').toSet();
    if (newSource.isNotEmpty) sources.add(newSource);

    content = _updateFrontmatterField(content, 'questionsAsked', questions.toString());
    content = _updateFrontmatterField(content, 'answersProvided', answers.toString());
    content = _updateFrontmatterField(content, 'notesContributed', notes.toString());
    content = _updateFrontmatterSourcesAndTags(content, sources.toList());

    final replacement = StringBuffer()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln();
    _appendContributions(replacement, contributions);
    replacement.write('<!-- AUTO_GENERATED_END -->');

    content = content.replaceAllMapped(
      RegExp(r'<!-- AUTO_GENERATED_START -->.*?<!-- AUTO_GENERATED_END -->', dotAll: true),
      (_) => replacement.toString(),
    );
    file.writeAsStringSync(content);
  }

  void _appendContributions(StringBuffer buffer, PersonContributions contributions) {
    _deduplicateAndSort(contributions);

    if (contributions.questions.isNotEmpty) {
      buffer.writeln('## Questions Asked');
      buffer.writeln();
      for (final q in contributions.questions) {
        buffer.writeln('- [[../../questions/${q.id}|${q.id}]] - ${q.date}');
      }
      buffer.writeln();
    }
    if (contributions.answers.isNotEmpty) {
      buffer.writeln('## Answers Provided');
      buffer.writeln();
      for (final a in contributions.answers) {
        buffer.writeln('- [[../../answers/${a.id}|${a.id}]] - ${a.date}');
      }
      buffer.writeln();
    }
    if (contributions.notes.isNotEmpty) {
      buffer.writeln('## Notes Contributed');
      buffer.writeln();
      for (final n in contributions.notes) {
        buffer.writeln('- [[../../notes/${n.id}|${n.id}]] - ${n.date}');
      }
      buffer.writeln();
    }
    if (contributions.topics.isNotEmpty) {
      buffer.writeln('## Topics');
      buffer.writeln();
      for (final t in contributions.topics.where((t) => t.count > 0)) {
        final plural = t.count > 1 ? 's' : '';
        buffer.writeln('- [[../../topics/${t.topicId}|${t.topicId}]] - ${t.count} contribution$plural');
      }
      buffer.writeln();
    }
  }

  void _deduplicateAndSort(PersonContributions contributions) {
    final questions = _dedupeItems(contributions.questions)..sort((a, b) => _extractIdNumber(a.id).compareTo(_extractIdNumber(b.id)));
    final answers = _dedupeItems(contributions.answers)..sort((a, b) => _extractIdNumber(a.id).compareTo(_extractIdNumber(b.id)));
    final notes = _dedupeItems(contributions.notes)..sort((a, b) => _extractIdNumber(a.id).compareTo(_extractIdNumber(b.id)));

    contributions.questions
      ..clear()
      ..addAll(questions);
    contributions.answers
      ..clear()
      ..addAll(answers);
    contributions.notes
      ..clear()
      ..addAll(notes);
    contributions.topics.sort((a, b) => b.count.compareTo(a.count));
  }

  List<ContributionItem> _dedupeItems(List<ContributionItem> items) {
    final seen = <String>{};
    return items.where((i) => seen.add(i.id)).toList();
  }

  int _extractIdNumber(String id) {
    final parts = id.split('_');
    if (parts.length == 2) return int.tryParse(parts[1]) ?? 0;
    return 0;
  }

  String _updateFrontmatterField(String content, String fieldName, String newValue) {
    return content.replaceFirstMapped(
      RegExp('($fieldName:\\s*)([^\\n]+)'),
      (m) => '${m.group(1)}$newValue',
    );
  }

  String _updateFrontmatterSourcesAndTags(String content, List<String> sources) {
    final sourcesYaml = '[${sources.map((s) => '"$s"').join(', ')}]';
    content = content.replaceFirstMapped(
      RegExp(r'(sources?:\s*)(?:\[[^\]]+\]|"[^"]+"|[^\n]+)'),
      (m) => '${m.group(1)}$sourcesYaml',
    );

    final tags = <String>['#person', ...sources.map(_formatSourceTag)];
    final tagsYaml = '[${tags.map((t) => '"$t"').join(', ')}]';
    content = content.replaceFirstMapped(
      RegExp(r'(tags:\s*)\[[^\]]+\]'),
      (m) => '${m.group(1)}$tagsYaml',
    );
    return content;
  }

  void _createAreaFileWithTopics(
    File areaFile,
    File areaDescFile,
    String title,
    String id,
    String? source,
    List<String> contributors,
    List<String> topics,
  ) {
    final existing = _loadExistingSourcesAndCreated(areaFile);
    final sources = existing.sources;
    if (source != null && !sources.contains(source)) sources.add(source);

    final fm = Frontmatter()
      ..['type'] = 'area'
      ..['title'] = title
      ..['id'] = id
      ..['sources'] = sources
      ..['contributors'] = (contributors.toList()..sort())
      ..['created'] = existing.created ?? currentUtcTimestamp();

    final buffer = _startEntityFileBuffer(fm, title, id);

    if (topics.isNotEmpty) {
      buffer.writeln('## Topics');
      buffer.writeln();
      for (final topic in topics.toList()..sort()) {
        final topicId = slugify(topic);
        buffer.writeln('- [[$topicId|$topic]]');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('## Key Contributors')
      ..writeln();
    for (final c in contributors.toList()..sort()) {
      buffer.writeln('- [[${normalizePersonName(c)}|$c]]');
    }

    buffer
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_START -->')
      ..writeln('## Statistics')
      ..writeln()
      ..writeln('*Statistics will be auto-generated here*')
      ..writeln()
      ..writeln('<!-- AUTO_GENERATED_END -->');

    areaFile.writeAsStringSync(buffer.toString());

    if (!areaDescFile.existsSync()) {
      areaDescFile.writeAsStringSync(
        '<!-- AI_CONTENT_START -->\n\nArea description will be generated by AI.\n\n<!-- AI_CONTENT_END -->\n',
      );
    }
  }

  void _createTopicFileWithAggregation(
    File topicFile,
    File topicDescFile,
    String title,
    String id,
    String? source,
    _TopicData data,
    AnalysisResult analysis,
  ) {
    final existing = _loadExistingSourcesAndCreated(topicFile);
    final sources = existing.sources;
    if (source != null && !sources.contains(source)) sources.add(source);

    final fm = Frontmatter()
      ..['type'] = 'topic'
      ..['title'] = title
      ..['id'] = id
      ..['sources'] = sources
      ..['contributors'] = data.contributors.toList()
      ..['created'] = existing.created ?? currentUtcTimestamp();

    if (data.tags.isNotEmpty) {
      fm['tags'] = data.tags.toList()..sort();
    }

    final buffer = _startEntityFileBuffer(fm, title, id)
      ..writeln('## Key Contributors')
      ..writeln();
    for (final c in data.contributors) {
      buffer.writeln('- [[${normalizePersonName(c)}|$c]]');
    }
    buffer.writeln();

    final qToA = Map<String, String>.from(data.qToA);
    final qToN = <String, Set<String>>{};
    final questionsInTopic = Set<String>.from(data.questions);
    final answersInTopic = Set<String>.from(data.answers);
    final notesInTopic = Set<String>.from(data.notes);

    for (final q in analysis.questions) {
      if (questionsInTopic.contains(q.id) && q.answeredBy != null && q.answeredBy!.isNotEmpty) {
        qToA[q.id] = q.answeredBy!;
      }
    }
    for (final n in analysis.notes) {
      if (notesInTopic.contains(n.id) && n.answersQuestions.isNotEmpty) {
        for (final qId in n.answersQuestions) {
          if (questionsInTopic.contains(qId)) {
            qToN.putIfAbsent(qId, () => <String>{})..add(n.id);
          }
        }
      }
    }

    final answersToExclude = <String>{};
    for (final answerId in answersInTopic) {
      final answer = analysis.answers.where((a) => a.id == answerId).firstOrNull;
      if (answer != null && answer.answersQuestion != null && questionsInTopic.contains(answer.answersQuestion)) {
        answersToExclude.add(answerId);
      } else if (data.linkedAnswers.contains(answerId)) {
        final qId = data.aToQ[answerId];
        if (qId != null && questionsInTopic.contains(qId)) answersToExclude.add(answerId);
      }
    }

    final notesToExclude = <String>{};
    for (final noteId in notesInTopic) {
      final note = analysis.notes.where((n) => n.id == noteId).firstOrNull;
      if (note != null && note.answersQuestions.isNotEmpty) {
        for (final qId in note.answersQuestions) {
          if (questionsInTopic.contains(qId)) {
            notesToExclude.add(noteId);
            break;
          }
        }
      }
    }

    final standaloneAnswers = answersInTopic.difference(answersToExclude);
    final standaloneNotes = notesInTopic.difference(notesToExclude);
    final allQuestionsWithContent = Set<String>.from(qToA.keys)..addAll(qToN.keys);
    final questionsWithoutAnswers = questionsInTopic.difference(allQuestionsWithContent);

    if (standaloneNotes.isNotEmpty) {
      buffer.writeln('## Notes');
      buffer.writeln();
      for (final nId in standaloneNotes) buffer.writeln('![[$nId]]\n');
    }
    if (allQuestionsWithContent.isNotEmpty) {
      buffer.writeln('## Questions with Answers');
      buffer.writeln();
      for (final qId in allQuestionsWithContent) buffer.writeln('![[$qId]]\n');
    }
    if (questionsWithoutAnswers.isNotEmpty) {
      buffer.writeln('## Unanswered Questions');
      buffer.writeln();
      for (final qId in questionsWithoutAnswers) buffer.writeln('![[$qId]]\n');
    }
    if (standaloneAnswers.isNotEmpty) {
      buffer.writeln('## Additional Answers');
      buffer.writeln();
      for (final aId in standaloneAnswers) buffer.writeln('![[$aId]]\n');
    }

    topicFile.writeAsStringSync(buffer.toString());

    if (!topicDescFile.existsSync()) {
      topicDescFile.writeAsStringSync(
        '<!-- AI_CONTENT_START -->\n\nTopic description will be generated by AI based on related questions, answers, and notes.\n\n<!-- AI_CONTENT_END -->\n',
      );
    }
  }

  String _formatSourceTag(String source) =>
      source.startsWith('source_') ? '#$source' : '#source_$source';

  void _recordQuestionLink(_TopicData data, String id, String? answeredBy) {
    data.questions.add(id);
    if (answeredBy != null && answeredBy.isNotEmpty) data.qToA[id] = answeredBy;
  }

  void _recordAnswerLink(_TopicData data, String id, String? answersQuestion) {
    data.answers.add(id);
    if (answersQuestion != null && answersQuestion.isNotEmpty) {
      data.linkedAnswers.add(id);
      data.aToQ[id] = answersQuestion;
    }
  }

  StringBuffer _startEntityFileBuffer(Frontmatter fm, String title, String id) => StringBuffer()
    ..writeln('---')
    ..write(fm.serialize())
    ..writeln('---')
    ..writeln()
    ..writeln('# $title')
    ..writeln()
    ..writeln('![[$id-desc]]')
    ..writeln();

  ({List<String> sources, String? created}) _loadExistingSourcesAndCreated(File file) {
    final sources = <String>[];
    String? created;
    if (file.existsSync()) {
      try {
        final fm = parseFrontmatter(file.readAsStringSync());
        sources.addAll(fm.getStringList('sources'));
        created = fm.getString('created');
      } catch (_) {}
    }
    return (sources: sources, created: created);
  }

  List<String> _buildEntityTags(List<String> originalTags, String source, String entityTag) =>
      <String>[
        if (!originalTags.any((t) => t == entityTag)) entityTag,
        if (!originalTags.any((t) => t.startsWith('#source_'))) _formatSourceTag(source),
        ...originalTags.where((t) => t != entityTag && !t.startsWith('#source_')),
      ];

  String _path(Directory dir) => dir.path;
}

class _TopicData {
  final Set<String> questions = <String>{};
  final Set<String> answers = <String>{};
  final Set<String> notes = <String>{};
  final Set<String> contributors = <String>{};
  final Set<String> tags = <String>{};
  final Map<String, String> qToA = <String, String>{};
  final Map<String, String> aToQ = <String, String>{};
  final Set<String> linkedAnswers = <String>{};
}
