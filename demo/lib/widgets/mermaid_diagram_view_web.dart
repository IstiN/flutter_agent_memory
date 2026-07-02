// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mermaid_renderer_web.dart' show renderMermaidDiagram;

/// Renders a Mermaid diagram inside a web platform view.
///
/// When [onNodeTap] is provided, tapping a record node in the diagram will
/// post its Mermaid id back to Flutter via `window.postMessage`.
class MermaidDiagramView extends StatefulWidget {
  final String diagram;
  final ValueChanged<String>? onNodeTap;

  const MermaidDiagramView({
    super.key,
    required this.diagram,
    this.onNodeTap,
  });

  @override
  State<MermaidDiagramView> createState() => _MermaidDiagramViewState();
}

class _MermaidDiagramViewState extends State<MermaidDiagramView> {
  StreamSubscription<html.MessageEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _listen();
    _render();
  }

  @override
  void didUpdateWidget(covariant MermaidDiagramView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagram != widget.diagram) {
      _render();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _listen() {
    _subscription = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is! Map) return;
      if (data['source'] != 'flutter_agent_memory') return;
      if (data['type'] != 'mermaid-node-click') return;
      final id = data['id'];
      if (id is String) {
        widget.onNodeTap?.call(id);
      }
    });
  }

  void _render() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      renderMermaidDiagram(widget.diagram);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: const HtmlElementView(viewType: 'mermaid-diagram'),
    );
  }
}
