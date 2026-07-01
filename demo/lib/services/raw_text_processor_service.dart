import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import 'vtt_utils.dart';

/// Decomposes a raw text dump into structured knowledge-base entries.
///
/// Reuses the package's [KBAnalysisAgent] so the demo and core library share
/// the same DMTools-derived prompt.
///
/// Long inputs are automatically chunked so they fit into models with modest
/// context windows, matching the DMTools [ChunkPreparation] behavior.
class RawTextProcessorService {
  final LlmProvider? provider;

  const RawTextProcessorService(this.provider);

  bool get available => provider != null;

  /// Default token limit per chunk, aligned with DMTools'
  /// `DEFAULT_PROMPT_CHUNK_TOKEN_LIMIT` (50000 tokens).
  /// Using ~4 characters per token as a rough approximation.
  static const int _maxChunkChars = 200000;

  /// If the normalized input exceeds this length we split it into chunks.
  static const int _chunkingThreshold = _maxChunkChars;

  Future<Map<String, dynamic>> process(String rawText) async {
    final p = provider;
    if (p == null) {
      throw StateError('LLM provider is not configured');
    }

    final normalized = _normalize(rawText);
    final agent = KBAnalysisAgent(p);

    final results = <AnalysisResult>[];
    if (normalized.length <= _chunkingThreshold) {
      final result = await agent.analyze(
        normalized,
        KBContext(),
        sourceName: 'raw-text',
      );
      results.add(result);
    } else {
      final chunks = _chunkText(normalized, _maxChunkChars);
      for (var i = 0; i < chunks.length; i++) {
        final result = await agent.analyze(
          chunks[i],
          KBContext(),
          sourceName: 'raw-text-part-${i + 1}',
        );
        results.add(result);
      }
    }

    final merged = _mergeResults(results);

    final allTopics = <String>{
      ...merged.questions.expand((q) => q.topics),
      ...merged.answers.expand((a) => a.topics),
      ...merged.notes.expand((n) => n.topics),
    }.where((t) => t.isNotEmpty).toList();

    final allTags = <String>{
      ...merged.questions.expand((q) => q.tags),
      ...merged.answers.expand((a) => a.tags),
      ...merged.notes.expand((n) => n.tags),
    }.where((t) => t.isNotEmpty).toList();

    String firstArea() {
      if (merged.questions.isNotEmpty) return merged.questions.first.area;
      if (merged.answers.isNotEmpty) return merged.answers.first.area;
      if (merged.notes.isNotEmpty) return merged.notes.first.area;
      return 'general';
    }

    return {
      'area': firstArea(),
      'topics': allTopics,
      'tags': allTags,
      'questions': merged.questions.map((q) => q.toJson()).toList(),
      'answers': merged.answers.map((a) => a.toJson()).toList(),
      'notes': merged.notes.map((n) => n.toJson()).toList(),
    };
  }

  /// Normalizes line endings and transforms VTT transcripts, matching
  /// DMTools' [KBFileReader] and [VTTUtils] behavior.
  static String _normalize(String text) {
    var normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u0085', '\n');

    if (VttUtils.isVttFormat(normalized)) {
      normalized = VttUtils.transformVtt(normalized, date: DateTime.now());
    }

    return normalized;
  }

  /// Splits [text] into chunks that do not exceed [maxChunkSize] characters,
  /// preferring paragraph boundaries.
  static List<String> _chunkText(String text, int maxChunkSize) {
    final paragraphs = text.split('\n\n');
    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
    }

    for (final paragraph in paragraphs) {
      if (paragraph.length > maxChunkSize) {
        flush();
        chunks.addAll(_chunkByBreaks(paragraph, maxChunkSize));
        continue;
      }
      if (buffer.length + paragraph.length + 2 > maxChunkSize) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.writeln('\n');
      buffer.write(paragraph);
    }
    flush();
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  /// Splits a large paragraph at natural boundaries: commas/brackets,
  /// then newlines, then spaces.
  static List<String> _chunkByBreaks(String text, int maxChunkSize) {
    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
    }

    var lastEnd = 0;
    while (lastEnd < text.length) {
      final remaining = text.substring(lastEnd);
      // Take up to maxChunkSize, then look back for a good break point.
      var take = remaining.length.clamp(0, maxChunkSize);
      if (take < remaining.length) {
        var bestBreak = take;
        // Look back up to 500 chars for a comma/bracket/newline/space.
        for (var i = take; i > take - 500 && i > 0; i--) {
          final ch = remaining[i - 1];
          if (ch == ',' || ch == '}' || ch == ']' || ch == '\n' || ch == ' ') {
            bestBreak = i;
            if (ch == ',' || ch == '}' || ch == ']' || ch == '\n') break;
          }
        }
        take = bestBreak;
      }
      buffer.write(remaining.substring(0, take));
      lastEnd += take;
      flush();
    }

    return chunks.where((c) => c.isNotEmpty).toList();
  }

  static AnalysisResult _mergeResults(List<AnalysisResult> results) {
    final questions = <Question>[];
    final answers = <Answer>[];
    final notes = <Note>[];
    for (final r in results) {
      questions.addAll(r.questions);
      answers.addAll(r.answers);
      notes.addAll(r.notes);
    }
    return AnalysisResult(
      questions: questions,
      answers: answers,
      notes: notes,
    );
  }
}
