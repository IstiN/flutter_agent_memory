import '../models/memory_level.dart';
import '../models/relation.dart';
import '../utils/frontmatter.dart';
import '../utils/slugify.dart';
import 'file_kb_storage_factory.dart'
    if (dart.library.html) 'file_kb_storage_factory_stub.dart';
import 'kb_storage.dart';

/// Builds an Obsidian-compatible graph view over the Markdown knowledge base.
///
/// The graph is derived from:
/// - explicit typed relations in note frontmatter,
/// - wiki-links (`[[target]]` / `[[target|title]]`),
/// - question/answer links,
/// - authorship edges.
///
/// Output is written to `GRAPH.md` as a Mermaid diagram plus a typed-edge
/// table. Everything stays Markdown, so Obsidian's native graph view and
/// backlinks work out of the box.
class _EdgeResolver {
  final Map<String, _GraphNode> nodes;
  final Map<String, String> bySlug = <String, String>{};

  _EdgeResolver(this.nodes) {
    for (final node in nodes.values) {
      bySlug[slugify(node.title)] = node.id;
      bySlug[slugify(node.id)] = node.id;
      bySlug[node.id.toLowerCase()] = node.id;
    }
  }

  String resolve(String raw) {
    final target = raw.split('|').first.trim();
    final lower = target.toLowerCase();
    if (nodes.containsKey(target)) return target;
    if (nodes.containsKey(lower)) return lower;
    final slug = slugify(target);
    if (bySlug.containsKey(slug)) return bySlug[slug]!;
    if (bySlug.containsKey(lower)) return bySlug[lower]!;
    return '';
  }
}

class KBGraphBuilder {
  final KbStorage storage;

  KBGraphBuilder(this.storage);

  /// Creates a graph builder for the classic Markdown file backend.
  factory KBGraphBuilder.file(dynamic kbDir) {
    return KBGraphBuilder(createFileKbStorage(kbDir));
  }

  /// Regenerates `GRAPH.md` in the knowledge-base root.
  Future<void> build({int maxMermaidNodes = 100}) async {
    final nodes = await _collectNodes();
    final edges = _collectEdges(nodes);
    await _writeGraphFile(nodes, edges, maxMermaidNodes: maxMermaidNodes);
  }

  Future<Map<String, _GraphNode>> _collectNodes() async {
    final nodes = <String, _GraphNode>{};

    await _scanEntityNodes(nodes, 'question');
    await _scanEntityNodes(nodes, 'answer');
    await _scanEntityNodes(nodes, 'note');

    await _scanFileNodes(nodes, 'people', 'person');
    await _scanFileNodes(nodes, 'areas', 'area');
    await _scanFileNodes(nodes, 'topics', 'topic');
    await _scanFileNodes(nodes, 'skills', 'skill');

    _ensureSharedNodes(nodes);

    return nodes;
  }

  Future<void> _scanEntityNodes(
    Map<String, _GraphNode> nodes,
    String type,
  ) async {
    for (final id in await storage.listEntityIds(type)) {
      try {
        final content = await storage.readEntity(type, id);
        if (content == null) continue;
        final fm = parseFrontmatter(content);
        if (fm.getString('id')?.toLowerCase() != id.toLowerCase()) continue;
        nodes[id] = _buildEntityNode(id, type, content, fm);
      } catch (_) {}
    }
  }

  _GraphNode _buildEntityNode(
    String id,
    String type,
    String content,
    Frontmatter fm,
  ) {
    final title = fm.getString('title') ?? _extractTitle(content) ?? id;
    return _GraphNode(
      id: id,
      type: type,
      title: title,
      path: storage.describeLocation(type, id),
      area: fm.getString('area') ?? '',
      level: _parseLevel(fm['level']),
      memoryType: fm.getString('memoryType'),
      tags: fm.getStringList('tags'),
      topics: fm.getStringList('topics'),
      content: content,
      fm: fm,
    );
  }

  int _parseLevel(dynamic raw) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? MemoryLevel.raw;
    return MemoryLevel.raw;
  }

  Future<void> _scanFileNodes(
    Map<String, _GraphNode> nodes,
    String prefix,
    String type,
  ) async {
    for (final path in await storage.listFilePaths(prefix)) {
      try {
        final content = await storage.readFile(path);
        if (content == null) continue;
        final fm = parseFrontmatter(content);
        final id = fm.getString('id') ?? _basenameWithoutExtension(path);
        if (id.isEmpty) continue;
        nodes[id] = _buildFileNode(id, type, path, content, fm);
      } catch (_) {}
    }
  }

  _GraphNode _buildFileNode(
    String id,
    String type,
    String path,
    String content,
    Frontmatter fm,
  ) {
    final title = fm.getString('title') ?? _extractTitle(content) ?? id;
    return _GraphNode(
      id: id,
      type: type,
      title: title,
      path: path,
      area: fm.getString('area') ?? '',
      level: MemoryLevel.concept,
      memoryType: fm.getString('memoryType'),
      tags: fm.getStringList('tags'),
      topics: fm.getStringList('topics'),
      content: content,
      fm: fm,
    );
  }

  void _ensureSharedNodes(Map<String, _GraphNode> nodes) {
    final entityNodes = nodes.values
        .where((n) => const {'question', 'answer', 'note'}.contains(n.type))
        .toList();
    for (final node in entityNodes) {
      _ensureAreaTagNode(nodes, node);
      _ensureTagNodes(nodes, node);
      _ensureTopicNodes(nodes, node);
      if (node.fm.getString('author')?.isNotEmpty == true) {
        final author = node.fm.getString('author')!;
        final authorId = _personId(author);
        _ensureTagNode(nodes, authorId, author, 'person');
      }
    }
  }

  void _ensureAreaTagNode(Map<String, _GraphNode> nodes, _GraphNode node) {
    if (node.area.isEmpty) return;
    _ensureTagNode(nodes, 'tag_${slugify(node.area)}', node.area, 'tag');
  }

  void _ensureTagNodes(Map<String, _GraphNode> nodes, _GraphNode node) {
    for (final tag in node.tags.where((t) => !t.startsWith('#'))) {
      _ensureTagNode(nodes, 'tag_${slugify(tag)}', tag, 'tag');
    }
  }

  void _ensureTopicNodes(Map<String, _GraphNode> nodes, _GraphNode node) {
    for (final topic in node.topics.where((t) => t.isNotEmpty)) {
      _ensureTagNode(nodes, 'tag_${slugify(topic)}', topic, 'tag');
    }
  }

  void _ensureTagNode(
    Map<String, _GraphNode> nodes,
    String id,
    String title,
    String type,
  ) {
    if (nodes.containsKey(id)) return;
    nodes[id] = _GraphNode(
      id: id,
      type: type,
      title: title,
      path: type,
      area: '',
      level: MemoryLevel.concept,
      tags: const [],
      topics: const [],
      content: '',
      fm: Frontmatter(),
    );
  }

  List<_GraphEdge> _collectEdges(Map<String, _GraphNode> nodes) {
    final edges = <_GraphEdge>{};
    final resolver = _EdgeResolver(nodes);

    for (final node in nodes.values) {
      _collectNodeEdges(node, edges, resolver, nodes);
    }

    _collectAnswerEdges(nodes, edges);
    _collectNoteAnswerEdges(nodes, edges);

    return _deduplicateWikiLinks(edges);
  }

  void _collectNodeEdges(
    _GraphNode node,
    Set<_GraphEdge> edges,
    _EdgeResolver resolver,
    Map<String, _GraphNode> nodes,
  ) {
    if (node.content.isNotEmpty) {
      _collectWikiEdges(node, edges, resolver);
      _collectRelationEdges(node, edges);
    }
    _collectMetadataEdges(node, edges, nodes);
  }

  void _collectWikiEdges(
    _GraphNode node,
    Set<_GraphEdge> edges,
    _EdgeResolver resolver,
  ) {
    final wikiRegex = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]');
    for (final m in wikiRegex.allMatches(node.content)) {
      final target = resolver.resolve(m.group(1)!);
      if (target.isNotEmpty) {
        _addEdge(edges, node.id, target, 'links_to');
      }
    }
  }

  void _collectRelationEdges(_GraphNode node, Set<_GraphEdge> edges) {
    for (final r in node.fm.getStringList('relations')) {
      final relation = Relation.fromFrontmatterString(node.id, r);
      _addEdge(
        edges,
        node.id,
        relation.target,
        relation.type,
        weight: relation.weight,
      );
    }
  }

  void _collectMetadataEdges(
    _GraphNode node,
    Set<_GraphEdge> edges,
    Map<String, _GraphNode> nodes,
  ) {
    if (!_isEntityNode(node.type)) return;

    _collectAreaEdge(node, edges);
    _collectTagEdges(node, edges);
    _collectTopicEdges(node, edges);
    _collectAuthorEdge(node, edges, nodes);
  }

  bool _isEntityNode(String type) =>
      const {'question', 'answer', 'note'}.contains(type);

  void _collectAreaEdge(_GraphNode node, Set<_GraphEdge> edges) {
    if (node.area.isEmpty) return;
    _addEdge(edges, node.id, 'tag_${slugify(node.area)}', 'area');
  }

  void _collectTagEdges(_GraphNode node, Set<_GraphEdge> edges) {
    for (final tag in node.tags.where((t) => !t.startsWith('#'))) {
      _addEdge(edges, node.id, 'tag_${slugify(tag)}', 'tagged');
    }
  }

  void _collectTopicEdges(_GraphNode node, Set<_GraphEdge> edges) {
    for (final topic in node.topics.where((t) => t.isNotEmpty)) {
      _addEdge(edges, node.id, 'tag_${slugify(topic)}', 'topic');
    }
  }

  void _collectAuthorEdge(
    _GraphNode node,
    Set<_GraphEdge> edges,
    Map<String, _GraphNode> nodes,
  ) {
    final author = node.fm.getString('author');
    if (author == null || author.isEmpty) return;
    final authorId = _personId(author);
    if (nodes.containsKey(authorId)) {
      _addEdge(edges, node.id, authorId, 'authored_by');
    }
  }

  void _collectAnswerEdges(
    Map<String, _GraphNode> nodes,
    Set<_GraphEdge> edges,
  ) {
    for (final node in nodes.values.where((n) => n.type == 'answer')) {
      final answer = node.fm.getString('answersQuestion');
      if (answer != null && answer.isNotEmpty) {
        _addEdge(edges, node.id, answer, 'answers');
      }
    }
  }

  void _collectNoteAnswerEdges(
    Map<String, _GraphNode> nodes,
    Set<_GraphEdge> edges,
  ) {
    for (final node in nodes.values.where((n) => n.type == 'note')) {
      for (final qid in node.fm.getStringList('answersQuestions')) {
        _addEdge(edges, node.id, qid, 'answers');
      }
    }
  }

  List<_GraphEdge> _deduplicateWikiLinks(Set<_GraphEdge> edges) {
    final edgeList = edges.toList();
    final typedKeys = edgeList
        .where((e) => e.type != 'links_to')
        .map((e) => '${e.source}|${e.target}')
        .toSet();
    return edgeList
        .where(
          (e) =>
              e.type != 'links_to' ||
              !typedKeys.contains('${e.source}|${e.target}'),
        )
        .toList();
  }

  void _addEdge(
    Set<_GraphEdge> edges,
    String source,
    String target,
    String type, {
    double weight = 1.0,
  }) {
    if (source.isEmpty || target.isEmpty || source == target) return;
    edges.add(
      _GraphEdge(source: source, target: target, type: type, weight: weight),
    );
  }

  String _personId(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return normalized.startsWith('-') ? normalized.substring(1) : normalized;
  }

  String? _extractTitle(String content) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(content);
    return match?.group(1)?.trim();
  }

  String _basenameWithoutExtension(String path) {
    final name = path.split('/').last;
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }

  Future<void> _writeGraphFile(
    Map<String, _GraphNode> nodes,
    List<_GraphEdge> edges, {
    required int maxMermaidNodes,
  }) async {
    final nodeList = nodes.values.toList();
    final edgeList = edges.toList();
    final mermaidIds = _selectMermaidIds(nodes, edgeList, maxMermaidNodes);
    final mermaidEdges = _filterMermaidEdges(edgeList, mermaidIds);

    final buffer = StringBuffer()
      ..writeln(_graphFrontmatter(nodeList.length, edgeList.length))
      ..writeln('# Knowledge Graph')
      ..writeln()
      ..writeln(_graphStats(nodes, nodeList.length, edgeList.length))
      ..writeln(_mermaidDiagram(nodes, mermaidIds, mermaidEdges))
      ..writeln(_typedRelations(edgeList));

    await storage.writeFile('GRAPH.md', buffer.toString());
  }

  Set<String> _selectMermaidIds(
    Map<String, _GraphNode> nodes,
    List<_GraphEdge> edges,
    int maxMermaidNodes,
  ) {
    if (nodes.length <= maxMermaidNodes) return nodes.keys.toSet();

    final entityTypes = const {'question', 'answer', 'note'};
    final priority = nodes.values
        .where(
          (n) => entityTypes.contains(n.type) && n.level >= MemoryLevel.concept,
        )
        .map((n) => n.id)
        .toSet();
    final seed = priority.take(maxMermaidNodes ~/ 2).toList();
    for (final e in edges) {
      if (seed.length >= maxMermaidNodes) break;
      if (priority.contains(e.source)) seed.add(e.target);
      if (priority.contains(e.target)) seed.add(e.source);
    }
    return seed.toSet();
  }

  List<_GraphEdge> _filterMermaidEdges(
    List<_GraphEdge> edges,
    Set<String> mermaidIds,
  ) => edges
      .where(
        (e) => mermaidIds.contains(e.source) && mermaidIds.contains(e.target),
      )
      .toList();

  String _graphFrontmatter(int nodeCount, int edgeCount) =>
      '---\n'
      'id: graph\n'
      'type: graph\n'
      'nodes: $nodeCount\n'
      'edges: $edgeCount\n'
      'generated: ${DateTime.now().toUtc().toIso8601String()}\n'
      '---\n\n';

  String _graphStats(
    Map<String, _GraphNode> nodes,
    int nodeCount,
    int edgeCount,
  ) =>
      '## Stats\n\n'
      '- **Nodes:** $nodeCount\n'
      '- **Edges:** $edgeCount\n'
      '- **Types:** ${nodes.values.map((n) => n.type).toSet().join(', ')}\n\n';

  String _mermaidDiagram(
    Map<String, _GraphNode> nodes,
    Set<String> mermaidIds,
    List<_GraphEdge> edges,
  ) {
    final buffer = StringBuffer()
      ..writeln('## Graph')
      ..writeln()
      ..writeln('```mermaid')
      ..writeln('graph TD;')
      ..writeln(
        '    %% Click nodes to open files (Obsidian supports mermaid click events in preview)',
      );
    for (final id in mermaidIds) {
      final node = nodes[id];
      if (node == null) continue;
      buffer.writeln('    ${_mermaidNodeLine(node)};');
    }
    for (final e in edges) {
      buffer.writeln(
        '    ${_mermaidId(e.source)} -->|${e.type}| ${_mermaidId(e.target)};',
      );
    }
    buffer.writeln('```\n');
    return buffer.toString();
  }

  String _mermaidNodeLine(_GraphNode node) {
    final label = _mermaidLabel(node.title);
    return '${_mermaidId(node.id)}["$label"]';
  }

  String _mermaidLabel(String title) {
    var label = title.length > 60 ? '${title.substring(0, 57)}...' : title;
    return label.replaceAll('"', '\\"');
  }

  // Mermaid node ids must not clash with keywords such as `graph`.
  String _mermaidId(String id) {
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return 'n_${safe}_id';
  }

  String _typedRelations(List<_GraphEdge> edges) {
    final buffer = StringBuffer()
      ..writeln('## Typed Relations')
      ..writeln();
    final byType = <String, List<_GraphEdge>>{};
    for (final e in edges) {
      byType.putIfAbsent(e.type, () => []).add(e);
    }
    for (final type in byType.keys.toList()..sort()) {
      buffer.writeln('### $type');
      buffer.writeln();
      for (final e in byType[type]!) {
        buffer.writeln('- [[${e.source}]] → [[${e.target}]]');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

class _GraphNode {
  final String id;
  final String type;
  final String title;
  final String path;
  final String area;
  final int level;
  final String? memoryType;
  final List<String> tags;
  final List<String> topics;
  final String content;
  final Frontmatter fm;

  _GraphNode({
    required this.id,
    required this.type,
    required this.title,
    required this.path,
    required this.area,
    required this.level,
    this.memoryType,
    required this.tags,
    required this.topics,
    required this.content,
    required this.fm,
  });
}

class _GraphEdge {
  final String source;
  final String target;
  final String type;
  final double weight;

  _GraphEdge({
    required this.source,
    required this.target,
    required this.type,
    this.weight = 1.0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GraphEdge &&
          source == other.source &&
          target == other.target &&
          type == other.type;

  @override
  int get hashCode => Object.hash(source, target, type);
}
