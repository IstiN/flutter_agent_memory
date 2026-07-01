import 'dart:convert';

import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

/// Processes a raw text dump into a structured knowledge-base note.
class RawTextProcessorService {
  final LlmProvider? provider;

  const RawTextProcessorService(this.provider);

  bool get available => provider != null;

  Future<Map<String, dynamic>> process(String rawText) async {
    final p = provider;
    if (p == null) {
      throw StateError('LLM provider is not configured');
    }

    final response = await p.chatMessages([
      const LlmMessage(
        role: 'system',
        content:
            'You extract a concise knowledge-base note from raw text. '
            'Return strictly JSON: '
            '{"title": "short title", "summary": "1-2 sentence summary", '
            '"tags": ["tag1", "tag2"], '
            '"area": "general|development|infrastructure|security|business"}.',
      ),
      LlmMessage(role: 'user', content: rawText),
    ]);

    final jsonText = _extractJson(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return {
      'title': (json['title'] ?? '').toString(),
      'summary': (json['summary'] ?? json['text'] ?? rawText).toString(),
      'tags': (json['tags'] as List? ?? [])
          .map((e) => e.toString())
          .where((t) => t.isNotEmpty)
          .toList(),
      'area': (json['area'] ?? 'general').toString(),
    };
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
