import '../agents/kb_tag_generator_agent.dart';
import '../llm/llm_provider.dart';
import '../utils/slugify.dart';

/// Enrichment metadata resolved for a new or updated memory record.
class EnrichedMemory {
  final String area;
  final List<String> topics;
  final List<String> tags;

  const EnrichedMemory({
    required this.area,
    required this.topics,
    required this.tags,
  });
}

/// Resolves area/topics/tags for memory records, optionally with an LLM.
///
/// Called on capture and update paths. When no [provider] is configured, or
/// the caller supplied explicit area and tags, the input values are kept and
/// no LLM round trip happens.
class KBMemoryEnrichment {
  final LlmProvider? provider;

  const KBMemoryEnrichment(this.provider);

  Future<EnrichedMemory> enrich(
    String text, {
    String? area,
    List<String>? topics,
    List<String>? tags,
  }) async {
    var resolvedArea = _nonEmpty(area) ?? 'general';
    var resolvedTopics = topics ?? const <String>[];
    var resolvedTags = tags ?? const <String>[];

    if (provider != null &&
        (resolvedArea == 'general' || resolvedTags.isEmpty)) {
      final enriched = await _enrichFromProvider(
        text,
        resolvedArea,
        resolvedTopics,
        resolvedTags,
      );
      resolvedArea = enriched.area;
      resolvedTopics = enriched.topics;
      resolvedTags = enriched.tags;
    }

    return EnrichedMemory(
      area: resolvedArea,
      topics: resolvedTopics,
      tags: resolvedTags,
    );
  }

  Future<EnrichedMemory> _enrichFromProvider(
    String text,
    String area,
    List<String> topics,
    List<String> tags,
  ) async {
    final generated = await KBTagGeneratorAgent(
      provider!,
    ).generateTags(text, maxTags: 5);
    final resolvedTags = tags.isEmpty ? generated : tags;
    final resolvedTopics = topics.isEmpty && generated.isNotEmpty
        ? [slugify(generated.first)]
        : topics;
    final resolvedArea = area == 'general' && generated.isNotEmpty
        ? _guessArea(generated)
        : area;
    return EnrichedMemory(
      area: resolvedArea,
      topics: resolvedTopics,
      tags: resolvedTags,
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String _guessArea(List<String> tags) {
    final lowered = tags.map((t) => t.toLowerCase()).toSet();
    final areaHints = <String, List<String>>{
      'development': [
        'dart',
        'flutter',
        'test',
        'testing',
        'unit-tests',
        'riverpod',
        'bloc',
      ],
      'infrastructure': [
        'docker',
        'kubernetes',
        'ci/cd',
        'github-actions',
        'deploy',
      ],
      'security': ['auth', 'security', 'oauth', 'jwt'],
      'business': ['product', 'requirements', 'meeting'],
    };
    for (final entry in areaHints.entries) {
      if (entry.value.any(lowered.contains)) return entry.key;
    }
    return 'general';
  }
}
