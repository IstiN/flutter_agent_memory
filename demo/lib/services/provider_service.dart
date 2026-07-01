import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';
import 'settings_service.dart';

enum ProviderType {
  ollama,
  openRouter,
  openAi,
  none;

  static ProviderType fromString(String value) {
    return switch (value.toLowerCase()) {
      'ollama' => ProviderType.ollama,
      'openai' => ProviderType.openAi,
      'open_router' || 'openrouter' => ProviderType.openRouter,
      _ => ProviderType.none,
    };
  }

  String get settingsValue => switch (this) {
    ProviderType.ollama => 'ollama',
    ProviderType.openRouter => 'openrouter',
    ProviderType.openAi => 'openai',
    ProviderType.none => 'none',
  };
}

/// Builds an LLM provider from persisted settings.
class ProviderService {
  final SettingsService settings;

  ProviderService(this.settings);

  /// The LLM configuration derived from persisted settings and environment
  /// variables (e.g. `OPENROUTER_MAX_TOKENS`).
  LlmConfig get baseConfig {
    return LlmConfig.fromEnvironment(
      provider: settings.provider,
      apiKey: settings.apiKey,
      baseUrl: settings.baseUrl,
      model: settings.model,
    );
  }

  LlmProvider? get provider {
    if (settings.provider == 'none') return null;
    final needsKey = settings.provider != 'ollama';
    if (settings.model.isEmpty) return null;
    if (needsKey && settings.apiKey.isEmpty) return null;
    return ProviderFactory.create(baseConfig);
  }

  String? get corsWarning {
    if (settings.provider == 'ollama') {
      return 'Ollama must be started with CORS headers enabled, e.g. '
          'OLLAMA_ORIGINS=* ollama serve.';
    }
    return null;
  }
}
