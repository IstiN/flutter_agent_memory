import 'dart:convert';

import 'package:http/http.dart' as http;

/// Model metadata returned by the OpenRouter `/api/v1/models` endpoint.
class OpenRouterModelInfo {
  final String id;

  /// Total context window (input + output) in tokens.
  final int contextLength;

  /// Maximum tokens the model may generate in a single response.
  final int maxCompletionTokens;

  const OpenRouterModelInfo({
    required this.id,
    required this.contextLength,
    required this.maxCompletionTokens,
  });
}

/// Fetches and caches OpenRouter model metadata.
///
/// The public `/api/v1/models` endpoint is CORS-enabled, so it can be called
/// directly from the Flutter web demo.
class OpenRouterModelService {
  static final Map<String, OpenRouterModelInfo> _cache = {};

  static Future<OpenRouterModelInfo?> fetchModelInfo(String modelId) async {
    if (_cache.containsKey(modelId)) {
      return _cache[modelId];
    }

    try {
      final response = await http.get(
        Uri.parse('https://openrouter.ai/api/v1/models'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
      if (data == null || data.isEmpty) {
        return null;
      }

      // Prefer an exact id match.
      Map<String, dynamic>? match;
      for (final model in data) {
        if (model['id'] == modelId) {
          match = model;
          break;
        }
      }

      // Fall back to the longest id that starts with the requested id
      // (e.g. the user picked `google/gemini-2.5-flash-lite-preview` but the
      // upstream id has a date suffix).
      if (match == null) {
        final candidates = data
            .where((model) => (model['id'] as String).startsWith(modelId))
            .toList();
        if (candidates.isNotEmpty) {
          candidates.sort(
            (a, b) => (b['id'] as String).length.compareTo(
                  (a['id'] as String).length,
                ),
          );
          match = candidates.first;
        }
      }

      if (match == null) {
        return null;
      }

      final topProvider = match['top_provider'] as Map<String, dynamic>?;
      final info = OpenRouterModelInfo(
        id: match['id'] as String,
        contextLength: (match['context_length'] as num?)?.toInt() ?? 0,
        maxCompletionTokens:
            (topProvider?['max_completion_tokens'] as num?)?.toInt() ?? 0,
      );

      _cache[modelId] = info;
      return info;
    } catch (_) {
      return null;
    }
  }
}
