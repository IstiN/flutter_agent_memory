import 'package:flutter/material.dart';

/// Stub implementation for non-web platforms.
class MermaidDiagramView extends StatelessWidget {
  final String diagram;
  final ValueChanged<String>? onNodeTap;

  const MermaidDiagramView({
    super.key,
    required this.diagram,
    this.onNodeTap,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
