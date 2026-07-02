import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../llm/gemma_llm_provider.dart';
import 'gemma_model_presets.dart';
import 'gemma_service.dart';
import 'settings_service.dart';

enum ProviderType {
  ollama,
  openRouter,
  openAi,
  gemma,
  none;

  static ProviderType fromString(String value) {
    return switch (value.toLowerCase()) {
      'ollama' => ProviderType.ollama,
      'openai' => ProviderType.openAi,
      'open_router' || 'openrouter' => ProviderType.openRouter,
      'gemma' => ProviderType.gemma,
      _ => ProviderType.none,
    };
  }

  String get settingsValue => switch (this) {
    ProviderType.ollama => 'ollama',
    ProviderType.openRouter => 'openrouter',
    ProviderType.openAi => 'openai',
    ProviderType.gemma => 'gemma',
    ProviderType.none => 'none',
  };
}

/// Builds an LLM provider from persisted settings.
class ProviderService {
  final SettingsService settings;
  final GemmaService gemmaService;

  ProviderService(this.settings, {required this.gemmaService});

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
    final type = ProviderType.fromString(settings.provider);
    if (type == ProviderType.none) return null;

    if (type == ProviderType.gemma) {
      final preset = findGemmaPreset(settings.model);
      if (preset == null) return null;
      return GemmaLlmProvider(gemmaService, preset);
    }

    final needsKey = type != ProviderType.ollama;
    if (settings.model.isEmpty) return null;
    if (needsKey && settings.apiKey.isEmpty) return null;
    return ProviderFactory.create(baseConfig);
  }

  bool get isGemma => ProviderType.fromString(settings.provider) == ProviderType.gemma;

  String? get corsWarning {
    final type = ProviderType.fromString(settings.provider);
    if (type == ProviderType.ollama) {
      return 'Ollama must be started with CORS headers enabled, e.g. '
          'OLLAMA_ORIGINS=* ollama serve.';
    }
    if (type == ProviderType.gemma) {
      return 'Models are downloaded from HuggingFace. Gated models may need a HuggingFace token.';
    }
    return null;
  }
}
