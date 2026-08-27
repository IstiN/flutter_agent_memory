/// The data is intentionally widget-free: a Flutter/macOS/iOS client calls
/// [MemoryOverviewService.build] (or `KBMemoryStore.overview()`), gets a
/// [MemoryOverview], renders it itself, and can persist or transport it via
/// `toJson()` / [MemoryOverview.fromJson].
library;

import 'dart:async';

import '../models/memory_level.dart';
import '../models/relation.dart';
import '../storage/kb_file_parser.dart';
import '../storage/kb_storage.dart';
import '../utils/date_utils.dart';

/// One record row of the memory overview list.
class MemoryOverviewEntry {
  final String id;
  final String type;
  final String text;
  final String author;
  final String? createdAt;
  final String? lastAccessedAt;
  final int accessCount;
  final double importance;
  final String area;
  final String? source;
  final int level;
  final String? memoryType;
  final String? validFrom;
  final String? validUntil;
  final List<String> tags;
  final List<String> topics;

  const MemoryOverviewEntry({
    required this.id,
    required this.type,
    required this.text,
    required this.author,
    this.createdAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    this.importance = 0.5,
    this.area = '',
    this.source,
    this.level = MemoryLevel.raw,
    this.memoryType,
    this.validFrom,
    this.validUntil,
    this.tags = const [],
    this.topics = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'text': text,
    'author': author,
    if (createdAt != null) 'createdAt': createdAt,
    if (lastAccessedAt != null) 'lastAccessedAt': lastAccessedAt,
    'accessCount': accessCount,
    'importance': importance,
    'area': area,
    if (source != null) 'source': source,
    'level': level,
    if (memoryType != null) 'memoryType': memoryType,
    if (validFrom != null) 'validFrom': validFrom,
    if (validUntil != null) 'validUntil': validUntil,
    'tags': tags,
    'topics': topics,
  };

  factory MemoryOverviewEntry.fromJson(Map<String, dynamic> json) =>
      MemoryOverviewEntry(
        id: json['id'] as String,
        type: json['type'] as String,
        text: json['text'] as String? ?? '',
        author: json['author'] as String? ?? '',
        createdAt: json['createdAt'] as String?,
        lastAccessedAt: json['lastAccessedAt'] as String?,
        accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
        area: json['area'] as String? ?? '',
        source: json['source'] as String?,
        level: (json['level'] as num?)?.toInt() ?? MemoryLevel.raw,
        memoryType: json['memoryType'] as String?,
        validFrom: json['validFrom'] as String?,
        validUntil: json['validUntil'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        topics: (json['topics'] as List?)?.cast<String>() ?? const [],
      );
}

/// A node of the memory overview graph — one memory record.
class MemoryGraphNode {
  final String id;
  final String type;
  final String title;
  final String area;
  final int level;
  final double importance;
  final int accessCount;
  final String? createdAt;
  final String? lastAccessedAt;
  final List<String> tags;
  final List<String> topics;

  const MemoryGraphNode({
    required this.id,
    required this.type,
    required this.title,
    this.area = '',
    this.level = MemoryLevel.raw,
    this.importance = 0.5,
    this.accessCount = 0,
    this.createdAt,
    this.lastAccessedAt,
    this.tags = const [],
    this.topics = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'area': area,
    'level': level,
    'importance': importance,
    'accessCount': accessCount,
    if (createdAt != null) 'createdAt': createdAt,
    if (lastAccessedAt != null) 'lastAccessedAt': lastAccessedAt,
    'tags': tags,
    'topics': topics,
  };

  factory MemoryGraphNode.fromJson(Map<String, dynamic> json) =>
      MemoryGraphNode(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String? ?? '',
        area: json['area'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? MemoryLevel.raw,
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
        accessCount: (json['accessCount'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String?,
        lastAccessedAt: json['lastAccessedAt'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        topics: (json['topics'] as List?)?.cast<String>() ?? const [],
      );
}

/// A typed edge between two graph nodes.
///
/// [type] mirrors the persisted relation vocabulary
/// (`supports`, `contradicts`, `related_to`, `answers`, `links_to`, ...).
class MemoryGraphEdge {
  final String source;
  final String target;
  final String type;
  final double weight;

  const MemoryGraphEdge({
    required this.source,
    required this.target,
    required this.type,
    this.weight = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    'type': type,
    'weight': weight,
  };

  factory MemoryGraphEdge.fromJson(Map<String, dynamic> json) =>
      MemoryGraphEdge(
        source: json['source'] as String,
        target: json['target'] as String,
        type: json['type'] as String,
        weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryGraphEdge &&
          source == other.source &&
          target == other.target &&
          type == other.type;

  @override
  int get hashCode => Object.hash(source, target, type);
}

/// The graph part of a memory overview: record nodes plus typed edges.
class MemoryOverviewGraph {
  final List<MemoryGraphNode> nodes;
  final List<MemoryGraphEdge> edges;
  final String generatedAt;

  const MemoryOverviewGraph({
    required this.nodes,
    required this.edges,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
    'generatedAt': generatedAt,
  };

  factory MemoryOverviewGraph.fromJson(Map<String, dynamic> json) =>
      MemoryOverviewGraph(
        nodes: (json['nodes'] as List? ?? const [])
            .map((n) => MemoryGraphNode.fromJson(n as Map<String, dynamic>))
            .toList(),
        edges: (json['edges'] as List? ?? const [])
            .map((e) => MemoryGraphEdge.fromJson(e as Map<String, dynamic>))
            .toList(),
        generatedAt: json['generatedAt'] as String? ?? '',
      );
}

/// Serializable snapshot of the memory store: record list + graph.
class MemoryOverview {
  final List<MemoryOverviewEntry> records;
  final MemoryOverviewGraph graph;
  final String generatedAt;

  const MemoryOverview({
    required this.records,
    required this.graph,
    required this.generatedAt,
  });

  int get questionCount => records.where((r) => r.type == 'question').length;
  int get answerCount => records.where((r) => r.type == 'answer').length;
  int get noteCount => records.where((r) => r.type == 'note').length;

  Map<String, dynamic> toJson() => {
    'records': records.map((r) => r.toJson()).toList(),
    'graph': graph.toJson(),
    'generatedAt': generatedAt,
    'counts': {
      'questions': questionCount,
      'answers': answerCount,
      'notes': noteCount,
    },
  };

  factory MemoryOverview.fromJson(Map<String, dynamic> json) => MemoryOverview(
    records: (json['records'] as List? ?? const [])
        .map((r) => MemoryOverviewEntry.fromJson(r as Map<String, dynamic>))
        .toList(),
    graph: MemoryOverviewGraph.fromJson(
      json['graph'] as Map<String, dynamic>? ?? const {},
    ),
    generatedAt: json['generatedAt'] as String? ?? '',
  );
}

/// Builds a [MemoryOverview] (record list + typed graph) from any
/// [KbStorage] backend. Pure data — no LLM calls, safe for UI snapshots.
class MemoryOverviewService {
  final KbStorage storage;
  final KBFileParser parser;

  MemoryOverviewService(this.storage, {KBFileParser? parser})
    : parser = parser ?? KBFileParser();

  /// Collects records and graph edges.
  ///
  /// [types]    subset of `question`, `answer`, `note` (default: all).
  /// [area]     only records from this area/scope (case-insensitive).
  /// [author]   only records authored by this author (case-insensitive).
  /// [tags]     any-match tag filter (case-insensitive).
  /// [limit]    maximum number of records (applied after sorting by
  ///            last-accessed, newest first); edges to filtered-out records
  ///            are dropped.
  Future<MemoryOverview> build({
    List<String>? types,
    String? area,
    String? author,
    List<String>? tags,
    int? limit,
  }) async {
    final entries = await _collectEntries(
      types: _normalizeTypes(types),
      area: area,
      author: author,
      tags: tags,
    );
    _sortByRecency(entries);
    final visible = _applyLimit(entries, limit);

    final edges = await _collectEdges(visible);
    final nodes = _toNodes(visible);

    final now = currentUtcTimestamp();
    return MemoryOverview(
      records: visible,
      graph: MemoryOverviewGraph(nodes: nodes, edges: edges, generatedAt: now),
      generatedAt: now,
    );
  }

  static const Set<String> _supportedTypes = {'question', 'answer', 'note'};

  List<String> _normalizeTypes(List<String>? types) {
    final wanted =
        types?.map((t) => t.toLowerCase()).toList() ??
        const ['question', 'answer', 'note'];
    return wanted.where(_supportedTypes.contains).toList();
  }

  Future<List<MemoryOverviewEntry>> _collectEntries({
    required List<String> types,
    String? area,
    String? author,
    List<String>? tags,
  }) async {
    final entries = <MemoryOverviewEntry>[];
    for (final type in types) {
      for (final id in await storage.listEntityIds(type)) {
        final entry = await _loadEntry(type, id, area, author, tags);
        if (entry != null) entries.add(entry);
      }
    }
    return entries;
  }

  Future<MemoryOverviewEntry?> _loadEntry(
    String type,
    String id,
    String? area,
    String? author,
    List<String>? tags,
  ) async {
    final content = await storage.readEntity(type, id);
    if (content == null) return null;
    try {
      final entry = _entryFor(type, content);
      if (entry == null) return null;
      if (!_matchesFilters(entry, area, author, tags)) return null;
      return entry;
    } catch (_) {
      // Skip unparsable records; an overview must never fail on one file.
      return null;
    }
  }

  bool _matchesFilters(
    MemoryOverviewEntry entry,
    String? area,
    String? author,
    List<String>? tags,
  ) {
    return _matchesArea(entry, area) &&
        _matchesAuthor(entry, author) &&
        _matchesTags(entry, tags);
  }

  bool _matchesArea(MemoryOverviewEntry entry, String? area) {
    if (area == null || area.isEmpty) return true;
    return entry.area.toLowerCase() == area.toLowerCase();
  }

  bool _matchesAuthor(MemoryOverviewEntry entry, String? author) {
    if (author == null || author.isEmpty) return true;
    return entry.author.toLowerCase() == author.toLowerCase();
  }

  bool _matchesTags(MemoryOverviewEntry entry, List<String>? tags) {
    if (tags == null || tags.isEmpty) return true;
    final requested = tags.map((t) => t.toLowerCase()).toSet();
    final owned = entry.tags.map((t) => t.toLowerCase()).toSet();
    return requested.intersection(owned).isNotEmpty;
  }

  List<MemoryOverviewEntry> _applyLimit(
    List<MemoryOverviewEntry> entries,
    int? limit,
  ) {
    if (limit != null && entries.length > limit) {
      return entries.sublist(0, limit);
    }
    return entries;
  }

  List<MemoryGraphNode> _toNodes(List<MemoryOverviewEntry> records) {
    return records
        .map(
          (e) => MemoryGraphNode(
            id: e.id,
            type: e.type,
            title: e.text,
            area: e.area,
            level: e.level,
            importance: e.importance,
            accessCount: e.accessCount,
            createdAt: e.createdAt,
            lastAccessedAt: e.lastAccessedAt,
            tags: e.tags,
            topics: e.topics,
          ),
        )
        .toList();
  }

  void _sortByRecency(List<MemoryOverviewEntry> entries) {
    DateTime stamp(MemoryOverviewEntry e) =>
        DateTime.tryParse(e.lastAccessedAt ?? '') ??
        DateTime.tryParse(e.createdAt ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    entries.sort((a, b) => stamp(b).compareTo(stamp(a)));
  }

  MemoryOverviewEntry? _entryFor(String type, String content) {
    switch (type) {
      case 'question':
        final q = parser.parseQuestion(content);
        return _fromParts(
          id: q.id,
          type: 'question',
          text: q.text,
          author: q.author,
          createdAt: q.date,
          lastAccessedAt: q.lastAccessedAt,
          accessCount: q.accessCount,
          importance: q.importance,
          area: q.area,
          tags: q.tags,
          topics: q.topics,
        );
      case 'answer':
        final a = parser.parseAnswer(content);
        return _fromParts(
          id: a.id,
          type: 'answer',
          text: a.text,
          author: a.author,
          createdAt: a.date,
          lastAccessedAt: a.lastAccessedAt,
          accessCount: a.accessCount,
          importance: a.importance,
          area: a.area,
          tags: a.tags,
          topics: a.topics,
        );
      case 'note':
        final n = parser.parseNote(content);
        return MemoryOverviewEntry(
          id: n.id,
          type: 'note',
          text: n.text,
          author: n.author,
          createdAt: n.date,
          lastAccessedAt: n.lastAccessedAt,
          accessCount: n.accessCount,
          importance: n.importance,
          area: n.area,
          source: _sourceTag(n.tags),
          level: n.level,
          memoryType: n.memoryType,
          validFrom: n.validFrom,
          validUntil: n.validUntil,
          tags: List.unmodifiable(n.tags),
          topics: List.unmodifiable(n.topics),
        );
    }
    return null;
  }

  MemoryOverviewEntry _fromParts({
    required String id,
    required String type,
    required String text,
    required String author,
    required String? createdAt,
    required String? lastAccessedAt,
    required int accessCount,
    required double importance,
    required String area,
    required List<String> tags,
    required List<String> topics,
  }) {
    return MemoryOverviewEntry(
      id: id,
      type: type,
      text: text,
      author: author,
      createdAt: createdAt,
      lastAccessedAt: lastAccessedAt,
      accessCount: accessCount,
      importance: importance,
      area: area,
      source: _sourceTag(tags),
      tags: List.unmodifiable(tags),
      topics: List.unmodifiable(topics),
    );
  }

  String? _sourceTag(List<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith('#source_')) return tag.substring('#source_'.length);
    }
    return null;
  }

  /// Derives typed edges between the visible records:
  /// - explicit note relations (`supports`, `contradicts`, ...),
  /// - `answers` links from answers/notes to questions,
  /// - wiki-link `[[target]]` references resolved to record ids.
  ///
  /// Edges pointing outside the visible record set are dropped so the client
  /// always receives a self-contained graph.
  Future<List<MemoryGraphEdge>> _collectEdges(
    List<MemoryOverviewEntry> records,
  ) async {
    final ids = records.map((r) => r.id.toLowerCase()).toSet();
    final edges = <MemoryGraphEdge>{};

    Future<void> edgesFor(String type, String id, String content) async {
      for (final relation in _relationsOf(type, content)) {
        if (!_isVisible(relation.target, ids)) continue;
        edges.add(
          MemoryGraphEdge(
            source: id,
            target: relation.target,
            type: relation.type,
            weight: relation.weight,
          ),
        );
      }
      for (final target in _wikiTargets(content)) {
        if (!_isVisible(target, ids)) continue;
        edges.add(
          MemoryGraphEdge(source: id, target: target, type: 'links_to'),
        );
      }
    }

    for (final type in _supportedTypes) {
      for (final id in await storage.listEntityIds(type)) {
        if (!ids.contains(id.toLowerCase())) continue;
        final content = await storage.readEntity(type, id);
        if (content == null) continue;
        try {
          await edgesFor(type, id, content);
        } catch (_) {}
      }
    }

    final sorted = edges.toList()
      ..sort((a, b) {
        final bySource = a.source.compareTo(b.source);
        if (bySource != 0) return bySource;
        final byTarget = a.target.compareTo(b.target);
        if (byTarget != 0) return byTarget;
        return a.type.compareTo(b.type);
      });
    return sorted;
  }

  bool _isVisible(String target, Set<String> ids) =>
      target.isNotEmpty && ids.contains(target.toLowerCase());

  /// Reads typed relations from a record's frontmatter.
  List<Relation> _relationsOf(String type, String content) {
    switch (type) {
      case 'note':
        final note = parser.parseNote(content);
        return [
          ...note.relations,
          ...note.answersQuestions.map(
            (qid) => Relation(
              source: note.id,
              target: qid,
              type: RelationType.answers,
            ),
          ),
        ];
      case 'answer':
        final answer = parser.parseAnswer(content);
        final target = answer.answersQuestion;
        if (target == null || target.isEmpty) return const [];
        return [
          Relation(
            source: answer.id,
            target: target,
            type: RelationType.answers,
          ),
        ];
      default:
        return const [];
    }
  }

  List<String> _wikiTargets(String content) {
    final regex = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]');
    final targets = <String>[];
    for (final match in regex.allMatches(content)) {
      targets.add(match.group(1)!.trim());
    }
    return targets;
  }
}
