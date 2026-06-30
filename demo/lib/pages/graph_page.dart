import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/kb_service.dart';
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

  Future<void> _buildGraph() async {
    setState(() => _loading = true);
    try {
      await widget.kbService.graphBuilder.build(maxMermaidNodes: 60);
      final md = await widget.kbService.storage.readFile('GRAPH.md');
      if (md == null) {
        setState(() => _error = 'GRAPH.md was not generated.');
        return;
      }
      final mermaid = _extractMermaid(md);
      setState(() {
        _markdown = md;
        _mermaid = mermaid;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
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
            Text('Error: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _buildGraph, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_markdown == null) {
      return const Center(child: Text('No graph yet.'));
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.article), text: 'Markdown'),
              Tab(icon: Icon(Icons.account_tree), text: 'Diagram'),
            ],
            onTap: (_) => setState(() {}),
          ),
          Expanded(
            child: TabBarView(
              children: [
                Markdown(data: _markdown!),
                _mermaid == null || _mermaid!.trim().isEmpty
                    ? const Center(child: Text('No Mermaid diagram found.'))
                    : MermaidView(diagram: _mermaid!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MermaidView extends StatefulWidget {
  final String diagram;

  const MermaidView({super.key, required this.diagram});

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'mermaid_${widget.diagram.hashCode}_${DateTime.now().microsecond}';
    MermaidRenderer.render(widget.diagram, _viewType);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
