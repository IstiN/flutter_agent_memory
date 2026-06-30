import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import 'package:demo/services/provider_service.dart';
import 'package:demo/services/kb_service.dart';

import '../test_helpers.dart';

void main() {
  group('KbService', () {
    test('uses injected in-memory storage', () async {
      final storage = InMemoryKbStorage();
      final settings = await createTestSettings();
      final service = KbService(settings, ProviderService(settings), storage: storage);

      expect(service.storage, same(storage));
      await service.store.addQuestion(text: 'What is Dart?', area: 'dev', tags: ['dart']);
      expect(storage.listEntityIds('question'), isNotEmpty);
    });

    test('clearAll removes records', () async {
      final service = await createTestKbService();
      await service.store.addQuestion(text: 'Q1', area: 'a');
      await service.clearAll();
      expect(await service.storage.listEntityIds('question'), isEmpty);
    });

    test('updateSettings rebuilds provider', () async {
      final service = await createTestKbService();
      expect(service.providerService.provider, isNull);

      await service.updateSettings(
        provider: 'openai',
        apiKey: 'key',
        model: 'gpt-4o-mini',
        baseUrl: '',
      );

      expect(service.providerService.provider, isNotNull);
      expect(service.settings.provider, 'openai');
    });
  });
}
