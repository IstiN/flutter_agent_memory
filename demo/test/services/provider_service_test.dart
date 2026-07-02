import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo/services/provider_service.dart';
import 'package:demo/services/settings_service.dart';

import 'fake_gemma_service.dart';

void main() {
  group('ProviderService', () {
    Future<ProviderService> makeService(Map<String, Object> values, {FakeGemmaService? gemma}) async {
      SharedPreferences.setMockInitialValues(values);
      final settings = await SettingsService.load();
      return ProviderService(settings, gemmaService: gemma ?? FakeGemmaService());
    }

    test('returns null when provider is none', () async {
      final service = await makeService({'provider': 'none', 'apiKey': '', 'model': ''});
      expect(service.provider, isNull);
    });

    test('returns null when key or model missing for OpenAI', () async {
      final noKey = await makeService({'provider': 'openai', 'apiKey': '', 'model': 'gpt-4o'});
      expect(noKey.provider, isNull);
      final noModel = await makeService({'provider': 'openai', 'apiKey': 'k', 'model': ''});
      expect(noModel.provider, isNull);
    });

    test('creates OpenAI provider when configured', () async {
      final service = await makeService({
        'provider': 'openai',
        'apiKey': 'key',
        'model': 'gpt-4o',
      });
      expect(service.provider, isNotNull);
    });

    test('creates OpenRouter provider when configured', () async {
      final service = await makeService({
        'provider': 'openrouter',
        'apiKey': 'key',
        'model': 'mistral',
      });
      expect(service.provider, isNotNull);
    });

    test('creates Ollama provider without API key', () async {
      final service = await makeService({
        'provider': 'ollama',
        'apiKey': '',
        'model': 'llama3',
      });
      expect(service.provider, isNotNull);
    });

    test('warns about CORS for Ollama', () async {
      final service = await makeService({'provider': 'ollama'});
      expect(service.corsWarning, contains('CORS'));
    });

    test('returns null for Gemma when no preset is selected', () async {
      final service = await makeService({'provider': 'gemma', 'model': ''});
      expect(service.provider, isNull);
    });

    test('returns Gemma provider when a valid preset is selected', () async {
      final service = await makeService({'provider': 'gemma', 'model': 'gemma3-270m'});
      expect(service.provider, isNotNull);
      expect(service.corsWarning, contains('HuggingFace'));
    });

    test('returns null for Gemma when preset id is unknown', () async {
      final service = await makeService({'provider': 'gemma', 'model': 'unknown'});
      expect(service.provider, isNull);
    });
  });
}
