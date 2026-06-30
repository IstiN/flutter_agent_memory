import 'dart:convert';

import 'package:flutter_agent_memory/src/agents/kb_consolidation_agent.dart';
import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

class _FakeProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model}) async {
    return jsonEncode({
      'summary': '# Summary\n\nTest memory summary.',
      'skills': [
        {
          'id': 'sk_1',
          'title': 'Handle async errors',
          'instruction': 'Use try/catch or Result wrappers.',
          'tags': ['dart', 'errors'],
        },
      ],
    });
  }

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async =>
      chat(messages.last.content);
}

void main() {
  test('produces summary and skills from records', () async {
    final agent = KBConsolidationAgent(_FakeProvider());
    final records = [
      const MemoryRecord(
        entityType: 'note',
        path: 'notes/n_0001.md',
        accessCount: 1,
        importance: 0.8,
      ),
    ];

    final result = await agent.consolidate(records);

    expect(result.summary, isNotEmpty);
    expect(result.skills, hasLength(1));
    expect(result.skills.first.title, 'Handle async errors');
  });
}
