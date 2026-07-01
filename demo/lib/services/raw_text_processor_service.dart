import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

/// Decomposes a raw text dump into structured knowledge-base entries.
///
/// Reuses the package's [KBAnalysisAgent] so the demo and core library share
/// the same DMTools-derived prompt.
class RawTextProcessorService {
  final LlmProvider? provider;

  const RawTextProcessorService(this.provider);

  bool get available => provider != null;

  Future<Map<String, dynamic>> process(String rawText) async {
    final p = provider;
    if (p == null) {
      throw StateError('LLM provider is not configured');
    }

    final agent = KBAnalysisAgent(p);
    final result = await agent.analyze(
      rawText,
      KBContext(),
      sourceName: 'raw-text',
    );

    final allTopics = <String>{
      ...result.questions.expand((q) => q.topics),
      ...result.answers.expand((a) => a.topics),
      ...result.notes.expand((n) => n.topics),
    }.where((t) => t.isNotEmpty).toList();

    final allTags = <String>{
      ...result.questions.expand((q) => q.tags),
      ...result.answers.expand((a) => a.tags),
      ...result.notes.expand((n) => n.tags),
    }.where((t) => t.isNotEmpty).toList();

    String firstArea() {
      if (result.questions.isNotEmpty) return result.questions.first.area;
      if (result.answers.isNotEmpty) return result.answers.first.area;
      if (result.notes.isNotEmpty) return result.notes.first.area;
      return 'general';
    }

    return {
      'area': firstArea(),
      'topics': allTopics,
      'tags': allTags,
      'questions': result.questions.map((q) => q.toJson()).toList(),
      'answers': result.answers.map((a) => a.toJson()).toList(),
      'notes': result.notes.map((n) => n.toJson()).toList(),
    };
  }
}
