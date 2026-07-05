import 'package:shared_preferences/shared_preferences.dart';

/// Persisted LLM provider settings.
class SettingsService {
  final SharedPreferences _prefs;

  static const _providerKey = 'provider';
  static const _apiKeyKey = 'apiKey';
  static const _modelKey = 'model';
  static const _baseUrlKey = 'baseUrl';
  static const _webLlmContextWindowSizeKey = 'webLlmContextWindowSize';
  static const _webLlmMaxOutputTokensKey = 'webLlmMaxOutputTokens';

  SettingsService(this._prefs);

  static Future<SettingsService> load() async {
    return SettingsService(await SharedPreferences.getInstance());
  }

  String get provider => _prefs.getString(_providerKey) ?? 'openrouter';

  String get apiKey => _prefs.getString(_apiKeyKey) ?? '';

  String get model => _prefs.getString(_modelKey) ?? '';

  String get baseUrl => _prefs.getString(_baseUrlKey) ?? '';

  int get webLlmContextWindowSize => _prefs.getInt(_webLlmContextWindowSizeKey) ?? 2048;

  int get webLlmMaxOutputTokens => _prefs.getInt(_webLlmMaxOutputTokensKey) ?? 512;

  bool get isConfigured => apiKey.isNotEmpty && model.isNotEmpty;

  Future<void> save({
    required String provider,
    required String apiKey,
    required String model,
    required String baseUrl,
    int? webLlmContextWindowSize,
    int? webLlmMaxOutputTokens,
  }) async {
    await _prefs.setString(_providerKey, provider);
    await _prefs.setString(_apiKeyKey, apiKey);
    await _prefs.setString(_modelKey, model);
    await _prefs.setString(_baseUrlKey, baseUrl);
    if (webLlmContextWindowSize != null) {
      await _prefs.setInt(_webLlmContextWindowSizeKey, webLlmContextWindowSize);
    }
    if (webLlmMaxOutputTokens != null) {
      await _prefs.setInt(_webLlmMaxOutputTokensKey, webLlmMaxOutputTokens);
    }
  }

  Future<void> clear() async => _prefs.clear();
}
