import 'dart:convert';

import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

/// Analyzes an image using a vision-capable LLM.
class ImageAnalysisService {
  final LlmProvider? provider;

  const ImageAnalysisService(this.provider);

  bool get available => provider != null;

  /// Returns `{description, tags}` from the image data URL.
  Future<Map<String, dynamic>> analyze(String imageDataUrl) async {
    final p = provider;
    if (p == null) {
      throw StateError('LLM provider is not configured');
    }

    final response = await p.chatMessages([
      const LlmMessage(
        role: 'system',
        content:
            'You analyze images for a knowledge base. Return strictly JSON: '
            '{"description": "concise description", "tags": ["tag1", "tag2"]}.',
      ),
      LlmMessage(
        role: 'user',
        content: 'Describe this image and suggest search tags.',
        images: [imageDataUrl],
      ),
    ]);

    final jsonText = _extractJson(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    final description = (json['description'] ?? json['text'] ?? response).toString();
    final tags = (json['tags'] as List? ?? [])
        .map((e) => e.toString())
        .where((t) => t.isNotEmpty)
        .toList();
    return {'description': description, 'tags': tags};
  }

  String _extractJson(String text) {
    final code = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(text)?.group(1);
    if (code != null) return code;
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }
}
