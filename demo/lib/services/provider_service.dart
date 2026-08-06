import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../llm/gemma_llm_provider.dart';
import '../llm/webllm_provider.dart';
import '../webllm/webllm_service.dart';
import 'gemma_model_presets.dart';
import 'gemma_service.dart';
import 'settings_service.dart';

enum ProviderType {
  ollama,
  openRouter,
  openAi,
  local,
  gemma,
  webllm,
  none;

  static ProviderType fromString(String value) {
    return switch (value.toLowerCase()) {
      'ollama' => ProviderType.ollama,
      'openai' => ProviderType.openAi,
      'open_router' || 'openrouter' => ProviderType.openRouter,
      'local' => ProviderType.local,
      'gemma' || 'flutter_gemma' => ProviderType.gemma,
      'webllm' => ProviderType.webllm,
      _ => ProviderType.none,
    };
  }

  String get settingsValue => switch (this) {
    ProviderType.ollama => 'ollama',
    ProviderType.openRouter => 'openrouter',
    ProviderType.openAi => 'openai',
    ProviderType.local => 'local',
    ProviderType.gemma => 'flutter_gemma',
    ProviderType.webllm => 'webllm',
    ProviderType.none => 'none',
  };

  String get displayName => switch (this) {
    ProviderType.ollama => 'Ollama',
    ProviderType.openRouter => 'OpenRouter',
    ProviderType.openAi => 'OpenAI',
    ProviderType.local => 'Local server',
    ProviderType.gemma => 'Flutter Gemma',
    ProviderType.webllm => 'WebLLM',
    ProviderType.none => 'None',
  };
}

/// Builds an LLM provider from persisted settings.
class ProviderService {
  final SettingsService settings;
  final GemmaService gemmaService;
  final WebLlmService webLlmService;

  ProviderService(
    this.settings, {
    required this.gemmaService,
    required this.webLlmService,
  });

  /// The LLM configuration derived from persisted settings and environment
  /// variables (e.g. `OPENROUTER_MAX_TOKENS`).
  LlmConfig get baseConfig {
    final config = LlmConfig.fromEnvironment(
      provider: settings.provider,
      apiKey: settings.apiKey,
      baseUrl: settings.baseUrl,
      model: settings.model,
    );
    final type = ProviderType.fromString(settings.provider);
    // On-device Gemma models have their own context-window metadata; make sure
    // the rest of the demo (chunking, limits) uses the preset value rather than
    // the generic default.
    if (type == ProviderType.gemma) {
      final preset = findGemmaPreset(settings.model);
      if (preset != null) {
        return config.copyWith(
          maxTokens: preset.maxOutputTokens,
          contextWindow: preset.maxTokens,
        );
      }
    }
    if (type == ProviderType.webllm) {
      return config.copyWith(
        maxTokens: settings.webLlmMaxOutputTokens,
        contextWindow: settings.webLlmContextWindowSize,
      );
    }
    return config;
  }

  LlmProvider? get provider {
    final type = ProviderType.fromString(settings.provider);
    if (type == ProviderType.none) return null;

    if (type == ProviderType.gemma) {
      final preset = findGemmaPreset(settings.model);
      if (preset == null) return null;
      return GemmaLlmProvider(gemmaService, preset);
    }

    if (type == ProviderType.webllm) {
      final preset = findWebLlmPreset(settings.model);
      if (preset == null) return null;
      return WebLlmProvider(webLlmService, preset, settings);
    }

    final needsKey = type != ProviderType.ollama && type != ProviderType.local;
    if (settings.model.isEmpty) return null;
    if (needsKey && settings.apiKey.isEmpty) return null;
    // Local servers are OpenAI-compatible. Use a dummy key when the user left
    // the field empty so the Authorization header is still well-formed.
    if (type == ProviderType.local && settings.apiKey.isEmpty) {
      return ProviderFactory.create(baseConfig.copyWith(apiKey: 'not-used'));
    }
    return ProviderFactory.create(baseConfig);
  }

  bool get isGemma =>
      ProviderType.fromString(settings.provider) == ProviderType.gemma;

  bool get isWebLlm =>
      ProviderType.fromString(settings.provider) == ProviderType.webllm;

  String? get corsWarning {
    final type = ProviderType.fromString(settings.provider);
    if (type == ProviderType.ollama) {
      return 'Ollama must be started with CORS headers enabled, e.g. '
          'OLLAMA_ORIGINS=* ollama serve.';
    }
    if (type == ProviderType.local) {
      return 'Use the full chat-completions URL, e.g. '
          'http://localhost:1234/v1/chat/completions. Enter any value in '
          'the API key field if your server requires one.';
    }
    if (type == ProviderType.gemma) {
      return 'Models are downloaded from HuggingFace. Gated models may need a HuggingFace token.';
    }
    if (type == ProviderType.webllm) {
      return 'Models are downloaded by the browser on first use and cached locally.';
    }
    return null;
  }
}
