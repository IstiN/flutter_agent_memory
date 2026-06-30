import 'dart:io';

import '../utils/dotenv_loader.dart';

/// Configuration values for LLM providers.
///
/// Reads from environment variables, a project-root `.env` file, and optional
/// explicit overrides. Override values take precedence, then environment
/// variables, then `.env`, then defaults.
class LlmConfig {
  final String providerName;
  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxTokens;
  final double temperature;
  final String maxTokensParamName;

  const LlmConfig({
    required this.providerName,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.maxTokens = 4096,
    this.temperature = -1,
    this.maxTokensParamName = 'max_completion_tokens',
  });

  factory LlmConfig.fromEnvironment({
    String provider = 'openai',
    String? apiKey,
    String? baseUrl,
    String? model,
    int? maxTokens,
    double? temperature,
    String? maxTokensParamName,
  }) {
    final env = Platform.environment;
    final dotEnv = loadDotEnv();
    final resolvedProvider = provider.toLowerCase();

    String providerPrefix(String key) {
      switch (resolvedProvider) {
        case 'openrouter':
          return 'OPENROUTER';
        case 'ollama':
          return 'OLLAMA';
        case 'openai':
        default:
          return 'OPENAI';
      }
    }

    String? envKey(String key) {
      final prefix = providerPrefix(key);
      final envValue =
          env['${prefix}_$key'] ?? env['${prefix}_${key.toUpperCase()}'];
      if (envValue != null && envValue.isNotEmpty) return envValue;

      final dotEnvValue =
          dotEnv['${prefix}_$key'] ?? dotEnv['${prefix}_${key.toUpperCase()}'];
      if (dotEnvValue != null && dotEnvValue.isNotEmpty) return dotEnvValue;

      return null;
    }

    String defaultBaseUrl() {
      switch (resolvedProvider) {
        case 'openrouter':
          return 'https://openrouter.ai/api/v1/chat/completions';
        case 'ollama':
          return 'https://ollama.com/v1/chat/completions';
        case 'openai':
        default:
          return 'https://api.openai.com/v1/chat/completions';
      }
    }

    var resolvedBaseUrl =
        baseUrl ??
        envKey('BASE_PATH') ??
        envKey('BASE_URL') ??
        defaultBaseUrl();
    if (resolvedProvider == 'ollama' &&
        !resolvedBaseUrl.endsWith('/v1/chat/completions')) {
      resolvedBaseUrl =
          '${resolvedBaseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/chat/completions';
    }

    return LlmConfig(
      providerName: resolvedProvider,
      apiKey: apiKey ?? envKey('API_KEY') ?? '',
      baseUrl: resolvedBaseUrl,
      model: model ?? envKey('MODEL') ?? '',
      maxTokens: maxTokens ?? int.tryParse(envKey('MAX_TOKENS') ?? '') ?? 4096,
      temperature:
          temperature ?? double.tryParse(envKey('TEMPERATURE') ?? '') ?? -1,
      maxTokensParamName:
          maxTokensParamName ??
          (envKey('MAX_TOKENS_PARAM_NAME')?.isNotEmpty == true
              ? envKey('MAX_TOKENS_PARAM_NAME')!
              : 'max_completion_tokens'),
    );
  }

  bool get isConfigured => apiKey.isNotEmpty && model.isNotEmpty;
}
