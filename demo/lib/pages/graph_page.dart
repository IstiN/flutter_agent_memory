import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mermaid_renderer.dart';

class GraphPage extends StatefulWidget {
  final KbService kbService;

  const GraphPage({super.key, required this.kbService});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  String? _markdown;
  String? _mermaid;
  bool _loading = false;
  String? _error;
  int _nodeCount = 0;
  int _edgeCount = 0;

  Future<void> _buildGraph() async {
    setState(() => _loading = true);
    try {
      await widget.kbService.graphBuilder.build(maxMermaidNodes: 80);
      final md = await widget.kbService.storage.readFile('GRAPH.md');
      if (md == null) {
        setState(() => _error = 'GRAPH.md was not generated.');
        return;
      }
      final stats = _extractStats(md);
      setState(() {
        _markdown = md;
        _mermaid = _extractMermaid(md);
        _nodeCount = stats.$1;
        _edgeCount = stats.$2;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  (int, int) _extractStats(String markdown) {
    final nodes = RegExp(r'nodes:\s*(\d+)').firstMatch(markdown)?.group(1);
    final edges = RegExp(r'edges:\s*(\d+)').firstMatch(markdown)?.group(1);
    return (int.tryParse(nodes ?? '') ?? 0, int.tryParse(edges ?? '') ?? 0);
  }

  String? _extractMermaid(String markdown) {
    final match = RegExp(
      r'```mermaid\n([\s\S]*?)\n```',
      multiLine: true,
    ).firstMatch(markdown);
    return match?.group(1);
  }

  @override
  void initState() {
    super.initState();
    _buildGraph();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _markdown == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              'Error: $_error',
              style: const TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 16),
            GlowButton(onPressed: _buildGraph, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_markdown == null) {
      return const Center(
        child: Text('No graph yet.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _StatsBar(nodeCount: _nodeCount, edgeCount: _edgeCount),
          TabBar(
            indicatorColor: AppColors.primaryGlow,
            labelColor: AppColors.primaryGlow,
            unselectedLabelColor: AppColors.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.article), text: 'Markdown'),
              Tab(icon: Icon(Icons.account_tree), text: 'Diagram'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Container(
                  color: AppColors.surface,
                  child: Markdown(
                    data: _markdown!,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      h1: const TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.bold),
                      h2: const TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w600),
                      h3: const TextStyle(color: AppColors.primaryGlow, fontSize: 16, fontWeight: FontWeight.w600),
                      p: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                      code: TextStyle(
                        color: AppColors.secondaryGlow,
                        backgroundColor: AppColors.surfaceHigh,
                        fontSize: 13,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                _mermaid == null || _mermaid!.trim().isEmpty
                    ? const Center(
                        child: Text(
                          'No Mermaid diagram found.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : _DiagramView(diagram: _mermaid!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final int nodeCount;
  final int edgeCount;

  const _StatsBar({required this.nodeCount, required this.edgeCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: _StatCard(label: 'Nodes', value: nodeCount, color: AppColors.primary)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: 'Edges', value: edgeCount, color: AppColors.secondary)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _DiagramView extends StatefulWidget {
  final String diagram;

  const _DiagramView({required this.diagram});

  @override
  State<_DiagramView> createState() => _DiagramViewState();
}

class _DiagramViewState extends State<_DiagramView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      renderMermaidDiagram(widget.diagram);
    });
  }

  @override
  void didUpdateWidget(covariant _DiagramView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagram != widget.diagram) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        renderMermaidDiagram(widget.diagram);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: const HtmlElementView(viewType: 'mermaid-diagram'),
    );
  }
}
