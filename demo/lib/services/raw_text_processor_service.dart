import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

/// Decomposes a raw text dump into structured knowledge-base entries.
///
/// Reuses the package's [KBAnalysisAgent] so the demo and core library share
/// the same DMTools-derived prompt.
///
/// Long inputs (e.g. meeting transcripts) are automatically chunked so they
/// fit into models with modest context windows.
class RawTextProcessorService {
  final LlmProvider? provider;

  const RawTextProcessorService(this.provider);

  bool get available => provider != null;

  /// Approximate character budget per chunk. A single Latin/English character
  /// is roughly 1/4 of a token, so 80k chars is ~20k tokens. This leaves room
  /// for the DMTools system prompt and the model's completion budget in a
  /// typical 32k-context model.
  static const int _maxChunkChars = 80000;

  /// If the input exceeds this length we normalize and chunk it.
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

  /// Removes common transcript/markup noise (WEBVTT cues, timestamps,
  /// speaker tags) and collapses whitespace.
  static String _normalize(String text) {
    var normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final isVtt = normalized.contains('WEBVTT') ||
        normalized.contains('-->') ||
        normalized.contains('<v ');

    if (isVtt) {
      final buffer = StringBuffer();
      for (final line in normalized.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed == 'WEBVTT') continue;
        // Skip cue identifiers like "ec1f.../123-0".
        if (RegExp(r'^[\w\-]+/[\w\-]+$').hasMatch(trimmed)) continue;
        // Skip timestamp lines like "00:00:11.265 --> 00:00:16.404".
        if (RegExp(r'^\d{2}:\d{2}:\d{2}\.\d+\s*-->').hasMatch(trimmed)) {
          continue;
        }
        // Convert "<v Name>text</v>" to "Name: text".
        final speakerMatch = RegExp(r'^<v\s+([^>]+)>(.+?)</v>\s*$').firstMatch(trimmed);
        if (speakerMatch != null) {
          final speaker = speakerMatch.group(1)!.trim();
          final content = speakerMatch.group(2)!.trim();
          buffer.writeln('$speaker: $content');
          continue;
        }
        buffer.writeln(trimmed);
      }
      normalized = buffer.toString();
    }

    return normalized
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
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
        chunks.addAll(_chunkByLines(paragraph, maxChunkSize));
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

  static List<String> _chunkByLines(String paragraph, int maxChunkSize) {
    final lines = paragraph.split('\n');
    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
    }

    for (final line in lines) {
      if (line.length > maxChunkSize) {
        flush();
        chunks.addAll(_chunkByWords(line, maxChunkSize));
        continue;
      }
      if (buffer.length + line.length + 1 > maxChunkSize) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(line);
    }
    flush();
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  static List<String> _chunkByWords(String line, int maxChunkSize) {
    final words = line.split(' ');
    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
    }

    for (final word in words) {
      if (buffer.length + word.length + 1 > maxChunkSize) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(word);
    }
    flush();
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
