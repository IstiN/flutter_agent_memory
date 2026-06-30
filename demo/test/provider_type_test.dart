import 'package:flutter_test/flutter_test.dart';
import 'package:demo/services/provider_service.dart';

void main() {
  group('ProviderType', () {
    test('parses provider strings', () {
      expect(ProviderType.fromString('ollama'), ProviderType.ollama);
      expect(ProviderType.fromString('openrouter'), ProviderType.openRouter);
      expect(ProviderType.fromString('openai'), ProviderType.openAi);
      expect(ProviderType.fromString('none'), ProviderType.none);
      expect(ProviderType.fromString('OPENROUTER'), ProviderType.openRouter);
    });

    test('produces settings values', () {
      expect(ProviderType.ollama.settingsValue, 'ollama');
      expect(ProviderType.openRouter.settingsValue, 'openrouter');
      expect(ProviderType.openAi.settingsValue, 'openai');
      expect(ProviderType.none.settingsValue, 'none');
    });
  });
}
