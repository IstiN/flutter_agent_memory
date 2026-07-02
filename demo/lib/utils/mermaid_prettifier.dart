/// Re-styles a generated Mermaid graph so it looks like a force-directed
/// knowledge graph: larger circular nodes, semantic colours, explicit tag and
/// people nodes, and clickable record nodes.
String prettifyMermaid(String src) {
  final nodeRe = RegExp(
    r'^(\s*)(n_[A-Za-z0-9_]+_id)\["([^"]*)"\];',
    multiLine: false,
  );
  final edgeRe = RegExp(
    r'^(\s*)(n_[A-Za-z0-9_]+_id)\s*--?>\|([^|]*)\|\s*(n_[A-Za-z0-9_]+_id);',
    multiLine: false,
  );

  final nodes = <String, _MNode>{};
  final edges = <_MEdge>[];

  for (final line in src.split('\n')) {
    final nodeMatch = nodeRe.firstMatch(line);
    if (nodeMatch != null) {
      final id = nodeMatch.group(2)!;
      final label = nodeMatch.group(3)!;
      nodes[id] = _MNode(
        id: id,
        label: label,
        className: _classForNode(id, label),
      );
      continue;
    }
    final edgeMatch = edgeRe.firstMatch(line);
    if (edgeMatch != null) {
      edges.add(
        _MEdge(
          source: edgeMatch.group(2)!,
          target: edgeMatch.group(4)!,
          type: edgeMatch.group(3)!.trim(),
        ),
      );
    }
  }

  bool isTag(String id) => RegExp(r'^n_tag_.*_id$').hasMatch(id);
  bool isTopicOrArea(String id) => RegExp(r'^n_(topic|area)_.*_id$').hasMatch(id);
  bool isAgent(String id) => nodes[id]?.label.toLowerCase().trim() == 'agent';
  bool isRecord(String id) =>
      {'questionNode', 'answerNode', 'noteNode', 'fileNode'}.contains(nodes[id]?.className);

  final keptNodes = nodes.values
      .where((n) =>
          !isTopicOrArea(n.id) &&
          !isAgent(n.id) &&
          (isTag(n.id) || n.className != 'tagNode'))
      .toList();
  final keptEdges = edges
      .where((e) =>
          !isTopicOrArea(e.source) &&
          !isTopicOrArea(e.target) &&
          !isAgent(e.source) &&
          !isAgent(e.target) &&
          (isTag(e.source) || isTag(e.target) || e.type != 'tagged'))
      .toList();

  final buffer = StringBuffer()
    ..writeln('flowchart TD')
    ..writeln(
      "    %%{init: {'flowchart': {'curve': 'basis', 'nodeSpacing': 100, 'rankSpacing': 120, 'useMaxWidth': true}}}%%",
    )
    ..writeln('    classDef questionNode fill:#7C3AED,stroke:#A78BFA,stroke-width:2px,color:#fff,font-size:18px,padding:12px')
    ..writeln('    classDef answerNode fill:#0891B2,stroke:#67E8F9,stroke-width:2px,color:#fff,font-size:18px,padding:12px')
    ..writeln('    classDef noteNode fill:#DB2777,stroke:#F472B6,stroke-width:2px,color:#fff,font-size:18px,padding:12px')
    ..writeln('    classDef tagNode fill:#14B8A6,stroke:#5EEAD4,stroke-width:2px,color:#fff,font-size:18px,padding:12px')
    ..writeln('    classDef personNode fill:#4F46E5,stroke:#818CF8,stroke-width:2px,color:#fff,font-size:18px,padding:12px')
    ..writeln('    classDef fileNode fill:#475569,stroke:#94A3B8,stroke-width:2px,color:#fff,font-size:18px,padding:12px')
    ..writeln('    classDef defaultNode fill:#64748B,stroke:#94A3B8,stroke-width:2px,color:#fff,font-size:18px,padding:12px');

  for (final n in keptNodes) {
    final safeLabel = n.label.replaceAll('"', '\\"');
    buffer.writeln('    ${n.id}(("$safeLabel")):::${n.className};');
    if (isRecord(n.id)) {
      buffer.writeln('    click ${n.id} call famNodeClick("${n.id}")');
    }
  }
  for (final e in keptEdges) {
    buffer.writeln('    ${e.source} --> ${e.target};');
  }
  return buffer.toString();
}

String? recordIdFromMermaidNode(String mermaidId) {
  final match = RegExp(r'^n_(.+)_id$').firstMatch(mermaidId);
  if (match == null) return null;
  final raw = match.group(1)!;
  if (RegExp(r'^[qan]_\d+$').hasMatch(raw)) return raw;
  return null;
}

String _classForNode(String id, String label) {
  if (RegExp(r'^n_tag_.*_id$').hasMatch(id)) {
    return 'tagNode';
  }
  final lower = label.toLowerCase().trim();
  // Records created by the graph builder use ids like n_q_0001_id, n_a_0002_id, n_n_0003_id.
  if (RegExp(r'^n_[qan]_\d+_id$').hasMatch(id)) {
    if (lower.contains('?')) return 'questionNode';
    if (lower.contains('we decided') ||
        lower.contains('conclusion') ||
        lower.contains('use ') ||
        lower.contains('prioritise')) {
      return 'answerNode';
    }
    return 'noteNode';
  }
  if (lower.contains('meeting.vtt') ||
      lower.contains('.vtt') ||
      lower.contains('.md') ||
      lower.contains('.txt')) {
    return 'fileNode';
  }
  if (label.trim().startsWith('#')) {
    return 'tagNode';
  }
  // Short, clean labels that are not record ids are treated as people.
  if (label.length <= 20 && !RegExp(r'[?.,!;:(){}\[\]]').hasMatch(label)) {
    return 'personNode';
  }
  if (lower.contains('performance') ||
      lower.contains('scalability') ||
      lower.contains('considerations') ||
      lower.contains('maintainability')) {
    return 'noteNode';
  }
  return 'defaultNode';
}

class _MNode {
  final String id;
  final String label;
  final String className;

  const _MNode({
    required this.id,
    required this.label,
    required this.className,
  });
}

class _MEdge {
  final String source;
  final String target;
  final String type;

  const _MEdge({
    required this.source,
    required this.target,
    required this.type,
  });
}
