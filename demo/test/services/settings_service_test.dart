import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo/services/settings_service.dart';

void main() {
  group('SettingsService', () {
    test('loads defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsService.load();
      expect(settings.provider, 'openrouter');
      expect(settings.apiKey, '');
      expect(settings.model, '');
      expect(settings.baseUrl, '');
      expect(settings.isConfigured, false);
    });

    test('reads saved values', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'openai',
        'apiKey': 'secret',
        'model': 'gpt-4o-mini',
        'baseUrl': 'https://api.example.com',
      });
      final settings = await SettingsService.load();
      expect(settings.provider, 'openai');
      expect(settings.apiKey, 'secret');
      expect(settings.model, 'gpt-4o-mini');
      expect(settings.baseUrl, 'https://api.example.com');
      expect(settings.isConfigured, true);
    });

    test('save persists values', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsService.load();
      await settings.save(
        provider: 'ollama',
        apiKey: 'key',
        model: 'llama3',
        baseUrl: 'http://localhost:11434',
      );
      expect(settings.provider, 'ollama');
      expect(settings.apiKey, 'key');
      expect(settings.model, 'llama3');
      expect(settings.baseUrl, 'http://localhost:11434');
    });
  });
}
