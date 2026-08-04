import 'dart:io';

import '../../models/analysis_result.dart';
import '../../utils/frontmatter.dart';

/// Merges existing area files on disk with entities from the current analysis.
class AreaMerger {
  final String Function(Directory) _path;

  const AreaMerger({required String Function(Directory) path}) : _path = path;

  AreaMergeResult merge(
    AnalysisResult analysis,
    Directory outputDir,
    String sourceName,
  ) {
    final areaContributors = <String, Set<String>>{};
    final areaTopics = <String, Set<String>>{};
    final areasFromCurrentAnalysis = <String>{};

    void collectFromEntity(
      String? area,
      List<String>? topics,
      String? author,
    ) {
      if (area == null || area.isEmpty) return;
      areasFromCurrentAnalysis.add(area);
      areaContributors.putIfAbsent(area, () => <String>{});
      if (author != null && author.isNotEmpty) {
        areaContributors[area]!.add(author);
      }
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

    final areaDir = Directory('${_path(outputDir)}/areas');
    _mergeExistingAreas(areaDir, areaContributors, areaTopics);

    return AreaMergeResult(
      areaDir: areaDir,
      areaContributors: areaContributors,
      areaTopics: areaTopics,
      areasFromCurrentAnalysis: areasFromCurrentAnalysis,
      sourceName: sourceName,
    );
  }

  void _mergeExistingAreas(
    Directory areasDir,
    Map<String, Set<String>> areaContributors,
    Map<String, Set<String>> areaTopics,
  ) {
    if (!areasDir.existsSync()) return;

    for (final areaDir in areasDir.listSync().whereType<Directory>()) {
      _mergeSingleArea(areaDir, areaContributors, areaTopics);
    }
  }

  void _mergeSingleArea(
    Directory areaDir,
    Map<String, Set<String>> areaContributors,
    Map<String, Set<String>> areaTopics,
  ) {
    final areaFile = _areaFile(areaDir);
    if (areaFile == null || !areaFile.existsSync()) return;
    try {
      final content = areaFile.readAsStringSync();
      final title = parseFrontmatter(content).getString('title');
      if (title == null || title.isEmpty) return;

      _mergeAreaContributors(title, content, areaContributors);
      _mergeAreaTopicLinks(title, content, areaTopics);
    } catch (_) {}
  }

  File? _areaFile(Directory areaDir) {
    final areaId = areaDir.uri.pathSegments.reversed.firstWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );
    if (areaId.isEmpty) return null;
    return File('${areaDir.path}/$areaId.md');
  }

  void _mergeAreaContributors(
    String title,
    String content,
    Map<String, Set<String>> areaContributors,
  ) {
    final contributors = parseFrontmatter(content).getStringList('contributors');
    if (contributors.isNotEmpty) {
      areaContributors.putIfAbsent(title, () => <String>{})
        ..addAll(contributors);
    }
  }

  void _mergeAreaTopicLinks(
    String title,
    String content,
    Map<String, Set<String>> areaTopics,
  ) {
    final topicsSection = RegExp(
      r'##\s+Topics\s+(.+?)(?=##|<!--|\Z)',
      dotAll: true,
    ).firstMatch(content);
    if (topicsSection == null) return;

    final linkRegex = RegExp(r'\[\[([^|\]]+)\|([^\]]+)\]\]');
    for (final m in linkRegex.allMatches(topicsSection.group(1)!)) {
      areaTopics.putIfAbsent(title, () => <String>{})..add(m.group(2)!.trim());
    }
  }
}

/// Result of merging existing area files with the current analysis.
class AreaMergeResult {
  final Directory areaDir;
  final Map<String, Set<String>> areaContributors;
  final Map<String, Set<String>> areaTopics;
  final Set<String> areasFromCurrentAnalysis;
  final String sourceName;

  const AreaMergeResult({
    required this.areaDir,
    required this.areaContributors,
    required this.areaTopics,
    required this.areasFromCurrentAnalysis,
    required this.sourceName,
  });

  String? sourceToAdd(String area) =>
      areasFromCurrentAnalysis.contains(area) ? sourceName : null;
}
