import 'package:flutter_agent_memory/src/agents/kb_reranker_agent.dart';
import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/storage/kb_memory_store.dart';
import 'package:test/test.dart';

class _FakeProvider implements LlmProvider {
  @override
  String get defaultModel => 'fake';

  @override
  Future<String> chat(String prompt, {String? model, void Function()? onCancel}) async {
    return '''
RANKED_ID=n_0002
RANKED_ID=n_0001
''';
  }

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async => chat(messages.last.content);

  @override
  Stream<String> chatStream(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chat(prompt, model: model, onCancel: onCancel);
  }

  @override
  Stream<String> chatMessagesStream(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield await chatMessages(messages, model: model, onCancel: onCancel);
  }

  @override
  Future<void> cancel() async {}
}

MemoryRecord _noteRecord(String id, String text) {
  return MemoryRecord(
    entityType: 'note',
    path: 'notes/$id.md',
    note: Note(
      id: id,
      text: text,
      area: 'dev',
      topics: const [],
      tags: const [],
      author: 'agent',
      date: '2026-01-01T00:00:00Z',
      answersQuestions: const [],
      links: const [],
    ),
  );
}

void main() {
  test('reranks candidate records by id', () async {
    final agent = KBRerankerAgent(_FakeProvider());
    final candidates = [
      _noteRecord('n_0001', 'Dart tips'),
      _noteRecord('n_0002', 'Flutter state management'),
    ];

    final ranked = await agent.rerank('state in Flutter', candidates);

    expect(ranked, ['n_0002', 'n_0001']);
  });

  test('preserves single candidate', () async {
    final agent = KBRerankerAgent(_FakeProvider());
    final candidates = [_noteRecord('n_0001', 'Only one')];

    final ranked = await agent.rerank('anything', candidates);

    expect(ranked, ['n_0001']);
  });
}
