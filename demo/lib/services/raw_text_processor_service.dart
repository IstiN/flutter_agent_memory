import 'dart:convert';

import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

/// Decomposes a raw text dump into structured knowledge-base entries.
///
/// Mirrors the DMTools KB analysis agent: one source becomes multiple
/// questions, answers and notes with areas, topics, tags, authors and links.
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
            'You are an AI assistant specialized in analyzing chat conversations, messages, and documentation to extract structured knowledge.\n'
            'Your task is to identify themes, questions, answers, notes, links and expertise signals from the provided text.\n'
            'You must be THOROUGH and extract ALL valuable information - it is better to include borderline cases than to miss important content.\n\n'
            'Return ONLY valid JSON without markdown code blocks or explanatory text.\n'
            'Use ISO 8601 for any date fields.\n'
            'Assign temporary IDs: q_1, q_2, a_1, a_2, n_1, n_2 etc.\n'
            'Use these temporary IDs to link answers to questions: question.answeredBy = "a_1", answer.answersQuestion = "q_1".\n\n'
            'AREA (one top-level category per item): ai, platform, development, infrastructure, data, security, business, collaboration, or a specific technology such as docker, kubernetes, python, flutter.\n'
            'TOPICS: 1-3 specific themes like "openai-api-error-handling".\n'
            'TAGS: specific keywords like ["buildkit", "multi-stage"].\n\n'
            'JSON schema:\n'
            '{\n'
            '  "area": "top-level domain for the whole source",\n'
            '  "topics": ["global-topic-1"],\n'
            '  "tags": ["global-tag-1"],\n'
            '  "questions": [{\n'
            '    "id": "q_1",\n'
            '    "author": "Name or empty",\n'
            '    "text": "...",\n'
            '    "date": "ISO-8601 or empty",\n'
            '    "area": "...",\n'
            '    "topics": [],\n'
            '    "tags": [],\n'
            '    "answeredBy": "a_1 or empty",\n'
            '    "links": [{"url": "...", "title": "..."}]\n'
            '  }],\n'
            '  "answers": [{\n'
            '    "id": "a_1",\n'
            '    "author": "Name or empty",\n'
            '    "text": "...",\n'
            '    "date": "ISO-8601 or empty",\n'
            '    "area": "...",\n'
            '    "topics": [],\n'
            '    "tags": [],\n'
            '    "answersQuestion": "q_1 or empty",\n'
            '    "quality": 0.8,\n'
            '    "links": [{"url": "...", "title": "..."}]\n'
            '  }],\n'
            '  "notes": [{\n'
            '    "id": "n_1",\n'
            '    "author": "Name or empty",\n'
            '    "text": "...",\n'
            '    "date": "ISO-8601 or empty",\n'
            '    "area": "...",\n'
            '    "topics": [],\n'
            '    "tags": [],\n'
            '    "links": [{"url": "...", "title": "..."}]\n'
            '  }]\n'
            '}\n\n'
            'Rules:\n'
            '- Questions: direct, indirect, requests for help, "I do not understand why..." etc.\n'
            '- Answers: direct replies, partial answers, code snippets, suggestions.\n'
            '- Notes: standalone valuable info, decisions, observations, links, warnings, task lists.\n'
            '- For notes: PRESERVE all details, do not summarize.\n'
            '- Extract EVERY URL you see.\n'
            '- Omit empty arrays/fields when possible.',
      ),
      LlmMessage(role: 'user', content: rawText),
    ]);

    final jsonText = _extractJson(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return {
      'area': (json['area'] ?? 'general').toString(),
      'topics': _stringList(json['topics']),
      'tags': _stringList(json['tags']),
      'questions': _mapList(json['questions'], (q) => {
        'id': (q['id'] ?? '').toString(),
        'author': (q['author'] ?? '').toString(),
        'text': (q['text'] ?? '').toString(),
        'date': (q['date'] ?? '').toString(),
        'area': (q['area'] ?? '').toString(),
        'topics': _stringList(q['topics']),
        'tags': _stringList(q['tags']),
        'answeredBy': (q['answeredBy'] ?? '').toString(),
        'links': _links(q['links']),
      }),
      'answers': _mapList(json['answers'], (a) => {
        'id': (a['id'] ?? '').toString(),
        'author': (a['author'] ?? '').toString(),
        'text': (a['text'] ?? '').toString(),
        'date': (a['date'] ?? '').toString(),
        'area': (a['area'] ?? '').toString(),
        'topics': _stringList(a['topics']),
        'tags': _stringList(a['tags']),
        'answersQuestion': (a['answersQuestion'] ?? '').toString(),
        'quality': (a['quality'] as num?)?.toDouble() ?? 0.8,
        'links': _links(a['links']),
      }),
      'notes': _mapList(json['notes'], (n) => {
        'id': (n['id'] ?? '').toString(),
        'author': (n['author'] ?? '').toString(),
        'text': (n['text'] ?? '').toString(),
        'date': (n['date'] ?? '').toString(),
        'area': (n['area'] ?? '').toString(),
        'topics': _stringList(n['topics']),
        'tags': _stringList(n['tags']),
        'links': _links(n['links']),
      }),
    };
  }

  List<String> _stringList(dynamic value) {
    return (value as List? ?? [])
        .map((e) => e.toString())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  List<Map<String, String>> _links(dynamic value) {
    return (value as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((m) => {
          'url': (m['url'] ?? '').toString(),
          'title': (m['title'] ?? '').toString(),
        })
        .where((m) => m['url']!.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _mapList(
    dynamic value,
    Map<String, dynamic> Function(Map<String, dynamic>) mapper,
  ) {
    return (value as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(mapper)
        .where((m) => (m['text'] ?? '').toString().isNotEmpty)
        .toList();
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
