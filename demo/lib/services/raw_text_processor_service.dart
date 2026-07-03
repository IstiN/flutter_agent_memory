import 'dart:developer' as dev;
import 'dart:math' show max;

import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import 'openrouter_model_service.dart';
import 'provider_service.dart';
import 'vtt_utils.dart';

/// Decomposes a raw text dump into structured knowledge-base entries.
///
/// Reuses the package's [KBAnalysisAgent] so the demo and core library share
/// the same DMTools-derived prompt.
///
/// Long inputs are automatically chunked. For OpenRouter models the chunk size
/// and output token limit are resolved dynamically from the model's published
/// metadata (`context_length` and `max_completion_tokens`). For other providers
/// a conservative DMTools-aligned default of 50k input tokens is used.
class RawTextProcessorService {
  final ProviderService _providerService;

  RawTextProcessorService(this._providerService);

  bool get available => _providerService.provider != null;

  /// Fallback chunk size aligned with DMTools' default chunk token limit.
  static const int _defaultInputChunkTokens = 50000;

  /// Reserve tokens for the system prompt, instructions, and output overhead.
  static const int _systemOverheadTokens = 1024;

  /// Approximate characters per token for Latin/Cyrillic text.
  static const int _charsPerToken = 4;

  Future<Map<String, dynamic>> process(String rawText) async {
    if (!available) {
      throw StateError('LLM provider is not configured');
    }

    dev.log('[RawTextProcessor] process start, inputLength=${rawText.length}');
    final normalized = _normalize(rawText);
    final limits = await _resolveLimits();
    dev.log('[RawTextProcessor] limits: inputChunkTokens=${limits.inputChunkTokens}, '
        'maxTokens=${_providerService.baseConfig.maxTokens}');

    final agent = KBAnalysisAgent(limits.provider);
    final maxChunkChars = limits.inputChunkTokens * _charsPerToken;

    final results = <AnalysisResult>[];
    if (normalized.length <= maxChunkChars) {
      dev.log('[RawTextProcessor] analyzing single chunk, chars=$normalized.length');
      final result = await agent.analyze(
        normalized,
        KBContext(),
        sourceName: 'raw-text',
      );
      dev.log('[RawTextProcessor] analysis done: questions=${result.questions.length}, '
          'answers=${result.answers.length}, notes=${result.notes.length}');
      results.add(result);
    } else {
      final chunks = _chunkText(normalized, maxChunkChars);
      dev.log('[RawTextProcessor] analyzing ${chunks.length} chunks');
      for (var i = 0; i < chunks.length; i++) {
        dev.log('[RawTextProcessor] chunk ${i + 1}/${chunks.length}, chars=${chunks[i].length}');
        final result = await agent.analyze(
          chunks[i],
          KBContext(),
          sourceName: 'raw-text-part-${i + 1}',
        );
        dev.log('[RawTextProcessor] chunk ${i + 1} done: questions=${result.questions.length}, '
            'answers=${result.answers.length}, notes=${result.notes.length}');
        results.add(result);
      }
    }

    final merged = _mergeResults(results);
    dev.log('[RawTextProcessor] merged: questions=${merged.questions.length}, '
        'answers=${merged.answers.length}, notes=${merged.notes.length}');

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

    final result = {
      'area': firstArea(),
      'topics': allTopics,
      'tags': allTags,
      'questions': merged.questions.map((q) => q.toJson()).toList(),
      'answers': merged.answers.map((a) => a.toJson()).toList(),
      'notes': merged.notes.map((n) => n.toJson()).toList(),
    };
    dev.log('[RawTextProcessor] process done, resultKeys=${result.keys.toList()}');
    return result;
  }

  /// Resolves the output token limit and input chunk size for the current
  /// provider/model combination.
  ///
  /// For OpenRouter the limits are fetched from `/api/v1/models` so the demo
  /// automatically uses the largest possible output and the largest safe input
  /// chunk (roughly half of the remaining context after reserving output).
  Future<_Limits> _resolveLimits() async {
    // Use the provider already built by [ProviderService] — this preserves
    // the Gemma on-device provider instead of routing it through the generic
    // [ProviderFactory] which only knows openai/openrouter/ollama.
    final provider = _providerService.provider!;
    var inputChunkTokens = _defaultInputChunkTokens;

    final baseConfig = _providerService.baseConfig;
    dev.log('[RawTextProcessor] _resolveLimits: provider=${baseConfig.providerName}, '
        'model=${baseConfig.model}, maxTokens=${baseConfig.maxTokens}');
    if (baseConfig.providerName == 'openrouter') {
      final info = await OpenRouterModelService.fetchModelInfo(baseConfig.model);
      if (info != null && info.contextLength > 0) {
        final outputTokens = info.maxCompletionTokens > 0
            ? info.maxCompletionTokens
            : baseConfig.maxTokens;
        // Leave roughly half of the post-output context for input so we stay
        // well below the model's total context window even with system prompts.
        inputChunkTokens = max(
          1000,
          (info.contextLength - outputTokens - _systemOverheadTokens) ~/ 2,
        );
      }
    }

    return _Limits(
      provider: provider,
      inputChunkTokens: inputChunkTokens,
    );
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

class _Limits {
  final LlmProvider provider;
  final int inputChunkTokens;

  _Limits({required this.provider, required this.inputChunkTokens});
}
