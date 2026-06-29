import 'llm_config.dart';
import 'llm_provider.dart';
import 'openai_provider.dart';
import 'openrouter_provider.dart';

/// Factory for creating the default [LlmProvider] based on [LlmConfig].
///
/// The provider can be overridden by supplying a custom implementation
/// directly to [KbOrchestrator] or by registering it here.
class ProviderFactory {
  static LlmProvider create(LlmConfig config) {
    switch (config.providerName) {
      case 'openrouter':
        return OpenRouterProvider(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
          defaultModel: config.model,
          maxTokens: config.maxTokens,
          temperature: config.temperature,
          maxTokensParamName: config.maxTokensParamName,
        );
      case 'ollama':
        return OpenAiProvider(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
          defaultModel: config.model,
          maxTokens: config.maxTokens,
          temperature: config.temperature,
          maxTokensParamName: config.maxTokensParamName,
        );
      case 'openai':
      default:
        return OpenAiProvider(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
          defaultModel: config.model,
          maxTokens: config.maxTokens,
          temperature: config.temperature,
          maxTokensParamName: config.maxTokensParamName,
        );
    }
  }
}
