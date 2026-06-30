import 'dart:convert';

import '../llm/llm_provider.dart';
import '../models/consolidation_result.dart';
import '../storage/kb_memory_store.dart' show MemoryRecord;
import '../utils/json_utils.dart';
import 'prompts/prompt_loader.dart';

/// Consolidates a set of memory records into a high-level summary and reusable
/// skill cards, similar to the global consolidation phase in advanced memory
/// systems.
class KBConsolidationAgent {
  final LlmProvider _provider;

  KBConsolidationAgent(this._provider);

  Future<ConsolidationResult> consolidate(
    List<MemoryRecord> records, {
    String? existingSummary,
    String extraInstructions = '',
  }) async {
    if (records.isEmpty) {
      return const ConsolidationResult(summary: '', skills: []);
    }

    final recordsText = records
        .asMap()
        .entries
        .map((e) {
          final i = e.key + 1;
          final r = e.value;
          final tags = r.tags.isEmpty ? '' : ' tags: ${r.tags.join(', ')}';
          return '$i. [${r.entityType}] ${r.title}\n${r.text}$tags';
        })
        .join('\n\n');

    final prompt = await PromptLoader.load('kb_consolidation.xml', {
      'recordsText': recordsText,
      'existingSummary': existingSummary ?? '(No existing summary)',
      'extraInstructions': extraInstructions,
    });

    final response = await _provider.chat(prompt);
    final jsonText = extractJsonFromMarkdown(response);
    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    return ConsolidationResult.fromJson(json);
  }
}
