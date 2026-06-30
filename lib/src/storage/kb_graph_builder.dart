import 'dart:io';

import '../models/memory_level.dart';
import '../models/relation.dart';
import '../utils/frontmatter.dart';
import '../utils/slugify.dart';
import 'kb_file_parser.dart';

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
class KBGraphBuilder {
  final Directory kbDir;
  final KBFileParser _parser;

  KBGraphBuilder(this.kbDir) : _parser = KBFileParser();

  /// Regenerates `GRAPH.md` in the knowledge-base root.
  void build({int maxMermaidNodes = 50}) {
    final nodes = _collectNodes();
    final edges = _collectEdges(nodes);
    _writeGraphFile(nodes, edges, maxMermaidNodes: maxMermaidNodes);
  }

  Map<String, _GraphNode> _collectNodes() {
    final nodes = <String, _GraphNode>{};

    void scan(Directory dir, String type) {
      if (!dir.existsSync()) return;
      for (final file in dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final content = file.readAsStringSync();
          final fm = parseFrontmatter(content);
          final id = fm.getString('id');
          if (id == null || id.isEmpty) continue;
          final title = fm.getString('title') ?? _extractTitle(content) ?? id;
          final levelRaw = fm['level'];
          final level = levelRaw is int
              ? levelRaw
              : (levelRaw is String ? int.tryParse(levelRaw) ?? MemoryLevel.raw : MemoryLevel.raw);
          nodes[id] = _GraphNode(
            id: id,
            type: type,
            title: title,
            path: file.path,
            area: fm.getString('area') ?? '',
            level: level,
            memoryType: fm.getString('memoryType'),
            tags: fm.getStringList('tags'),
          );
        } catch (_) {}
      }
    }

    scan(Directory('${kbDir.path}/questions'), 'question');
    scan(Directory('${kbDir.path}/answers'), 'answer');
    scan(Directory('${kbDir.path}/notes'), 'note');
    scan(Directory('${kbDir.path}/people'), 'person');
    scan(Directory('${kbDir.path}/areas'), 'area');
    scan(Directory('${kbDir.path}/topics'), 'topic');
    scan(Directory('${kbDir.path}/skills'), 'skill');

    // Synthetic nodes for MEMORY.md and GRAPH.md themselves.
    for (final name in ['MEMORY', 'GRAPH']) {
      final id = name.toLowerCase();
      nodes[id] = _GraphNode(
        id: id,
        type: 'index',
        title: name,
        path: '${kbDir.path}/$name.md',
        area: '',
        level: MemoryLevel.concept,
        tags: const [],
      );
    }

    return nodes;
  }

  List<_GraphEdge> _collectEdges(Map<String, _GraphNode> nodes) {
    final edges = <_GraphEdge>{};
    final bySlug = <String, String>{};
    for (final node in nodes.values) {
      bySlug[slugify(node.title)] = node.id;
      bySlug[slugify(node.id)] = node.id;
      bySlug[node.id.toLowerCase()] = node.id;
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

    void addEdge(String source, String target, String type, {double weight = 1.0}) {
      if (source.isEmpty || target.isEmpty || source == target) return;
      edges.add(_GraphEdge(source: source, target: target, type: type, weight: weight));
    }

    for (final node in nodes.values) {
      final file = File(node.path);
      if (!file.existsSync()) continue;
      final content = file.readAsStringSync();

      // Wiki-links.
      final wikiRegex = RegExp(r'\[\[([^\]|]+)(?:\|[^\]]+)?\]\]');
      for (final m in wikiRegex.allMatches(content)) {
        final target = resolve(m.group(1)!);
        if (target.isNotEmpty) addEdge(node.id, target, 'links_to');
      }

      // Explicit frontmatter relations (notes only).
      final fm = parseFrontmatter(content);
      final relations = fm.getStringList('relations');
      for (final r in relations) {
        final relation = Relation.fromFrontmatterString(node.id, r);
        addEdge(node.id, relation.target, relation.type, weight: relation.weight);
      }

      // Authorship.
      final author = fm.getString('author');
      if (author != null && author.isNotEmpty) {
        final authorId = _personId(author);
        if (nodes.containsKey(authorId)) addEdge(node.id, authorId, 'authored_by');
      }
    }

    // Question/answer links from answer files.
    final answersDir = Directory('${kbDir.path}/answers');
    if (answersDir.existsSync()) {
      for (final file in answersDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final answer = _parser.parseAnswer(file.readAsStringSync());
          if (answer.answersQuestion != null && answer.answersQuestion!.isNotEmpty) {
            addEdge(answer.id, answer.answersQuestion!, 'answers');
          }
        } catch (_) {}
      }
    }

    // Note -> answered questions.
    final notesDir = Directory('${kbDir.path}/notes');
    if (notesDir.existsSync()) {
      for (final file in notesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'))) {
        try {
          final note = _parser.parseNote(file.readAsStringSync());
          for (final qid in note.answersQuestions) {
            addEdge(note.id, qid, 'answers');
          }
        } catch (_) {}
      }
    }

    return edges.toList();
  }

  String _personId(String name) {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'-+'), '-');
    return normalized.startsWith('-') ? normalized.substring(1) : normalized;
  }

  String? _extractTitle(String content) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(content);
    return match?.group(1)?.trim();
  }

  void _writeGraphFile(
    Map<String, _GraphNode> nodes,
    List<_GraphEdge> edges, {
    required int maxMermaidNodes,
  }) {
    final nodeList = nodes.values.toList();
    final edgeList = edges.toList();

    // For the Mermaid diagram, prefer higher-level nodes plus their neighbors.
    final priority = nodeList.where((n) => n.level >= MemoryLevel.concept).map((n) => n.id).toSet();
    final seed = priority.take(maxMermaidNodes ~/ 2).toList();
    for (final e in edgeList) {
      if (seed.length >= maxMermaidNodes) break;
      if (priority.contains(e.source)) seed.add(e.target);
      if (priority.contains(e.target)) seed.add(e.source);
    }
    final mermaidIds = seed.toSet();
    final mermaidEdges = edgeList.where((e) => mermaidIds.contains(e.source) && mermaidIds.contains(e.target)).toList();

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: graph')
      ..writeln('type: graph')
      ..writeln('nodes: ${nodeList.length}')
      ..writeln('edges: ${edgeList.length}')
      ..writeln('generated: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('---')
      ..writeln()
      ..writeln('# Knowledge Graph')
      ..writeln()
      ..writeln('## Stats')
      ..writeln()
      ..writeln('- **Nodes:** ${nodeList.length}')
      ..writeln('- **Edges:** ${edgeList.length}')
      ..writeln('- **Types:** ${nodes.values.map((n) => n.type).toSet().join(', ')}')
      ..writeln()
      ..writeln('## Graph')
      ..writeln()
      ..writeln('```mermaid')
      ..writeln('graph TD;')
      ..writeln('    %% Click nodes to open files (Obsidian supports mermaid click events in preview)');

    for (final id in mermaidIds) {
      final node = nodes[id];
      if (node == null) continue;
      final label = node.title.replaceAll('"', '\\"');
      buffer.writeln('    ${node.id}["$label"];');
    }
    for (final e in mermaidEdges) {
      buffer.writeln('    ${e.source} -->|${e.type}| ${e.target};');
    }
    buffer
      ..writeln('```')
      ..writeln()
      ..writeln('## Typed Relations')
      ..writeln();

    final byType = <String, List<_GraphEdge>>{};
    for (final e in edgeList) {
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

    File('${kbDir.path}/GRAPH.md').writeAsStringSync(buffer.toString());
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

  _GraphNode({
    required this.id,
    required this.type,
    required this.title,
    required this.path,
    required this.area,
    required this.level,
    this.memoryType,
    required this.tags,
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
