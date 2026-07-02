import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// Platform detection that's safe for web and tests.
bool get _isDesktop {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

/// Curated on-device model presets for the Flutter Gemma provider.
///
/// Mirrors the model gallery from the Flutter Gemma example app, including
/// Gemma 4, Gemma 3 / Nano, Qwen, Phi, FunctionGemma and other supported
/// models. Each preset can carry a `baseUrl`, a web-specific URL and a
/// desktop-specific URL; [url] resolves the right one for the current platform.
class GemmaModelPreset {
  final String id;
  final String displayName;
  final String bestFor;
  final String size;
  final String baseUrl;
  final String? webUrl;
  final String? desktopUrl;
  final ModelType modelType;
  final ModelFileType fileType;
  final PreferredBackend preferredBackend;
  final bool needsAuth;
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;
  final bool supportImage;
  final bool supportAudio;
  final bool supportsFunctionCalls;
  final bool isThinking;
  final bool agentic;
  final int? maxNumImages;
  final bool? foregroundDownload;

  const GemmaModelPreset({
    required this.id,
    required this.displayName,
    required this.bestFor,
    required this.size,
    required this.baseUrl,
    this.webUrl,
    this.desktopUrl,
    required this.modelType,
    required this.fileType,
    this.preferredBackend = PreferredBackend.gpu,
    this.needsAuth = false,
    this.maxTokens = 1024,
    this.temperature = 1.0,
    this.topK = 64,
    this.topP = 0.95,
    this.supportImage = false,
    this.supportAudio = false,
    this.supportsFunctionCalls = false,
    this.isThinking = false,
    this.agentic = false,
    this.maxNumImages,
    this.foregroundDownload,
  });

  /// Resolves the download URL for the current platform.
  String get url {
    if (_isDesktop && desktopUrl != null && desktopUrl!.isNotEmpty) {
      return desktopUrl!;
    }
    if (kIsWeb && webUrl != null && webUrl!.isNotEmpty) {
      return webUrl!;
    }
    return baseUrl;
  }

  /// Unique filename used as the installed-model identity.
  String get filename {
    return url.split('/').last;
  }

  /// Whether this preset has a dedicated web URL.
  bool get supportsWeb => webUrl != null && webUrl!.isNotEmpty;

  /// Whether this preset has a dedicated desktop (.litertlm) URL.
  bool get supportsDesktop =>
      (desktopUrl != null && desktopUrl!.isNotEmpty) ||
      baseUrl.endsWith('.litertlm');
}

const List<GemmaModelPreset> gemmaModelPresets = [
  // === Gemma 4 (next-gen multimodal) ===
  GemmaModelPreset(
    id: 'gemma4-e2b-litertlm',
    displayName: 'Gemma 4 E2B IT',
    bestFor: 'Next-gen multimodal — text, image & audio',
    size: '2.4 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    webUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 4096,
    supportImage: true,
    supportAudio: true,
    supportsFunctionCalls: true,
    isThinking: true,
    agentic: true,
    maxNumImages: 4,
  ),
  GemmaModelPreset(
    id: 'gemma4-e4b-litertlm',
    displayName: 'Gemma 4 E4B IT',
    bestFor: 'Next-gen multimodal — higher capacity',
    size: '4.3 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    webUrl:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 4096,
    supportImage: true,
    supportAudio: true,
    supportsFunctionCalls: true,
    isThinking: true,
    agentic: true,
    maxNumImages: 4,
  ),
  GemmaModelPreset(
    id: 'gemma4-e2b-intel-lnl',
    displayName: 'Gemma 4 E2B IT (Intel NPU — Lunar Lake)',
    bestFor: 'Intel NPU on Windows desktop',
    size: '2.96 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it_intel_LNL.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it_intel_LNL.litertlm',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    preferredBackend: PreferredBackend.npu,
    maxTokens: 4096,
    supportsFunctionCalls: true,
    isThinking: true,
  ),
  GemmaModelPreset(
    id: 'gemma4-e2b-intel-ptl',
    displayName: 'Gemma 4 E2B IT (Intel NPU — Panther Lake)',
    bestFor: 'Intel NPU on Windows desktop',
    size: '2.95 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it_intel_PTL.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it_intel_PTL.litertlm',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
    preferredBackend: PreferredBackend.npu,
    maxTokens: 4096,
    supportsFunctionCalls: true,
    isThinking: true,
  ),
  GemmaModelPreset(
    id: 'gemma4-e2b',
    displayName: 'Gemma 4 E2B IT (Web/MediaPipe)',
    bestFor: 'Web-only MediaPipe build',
    size: '2.0 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.task',
    webUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.task',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.task,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 4096,
    supportImage: true,
    supportsFunctionCalls: true,
    isThinking: true,
    maxNumImages: 4,
  ),
  GemmaModelPreset(
    id: 'gemma4-e4b',
    displayName: 'Gemma 4 E4B IT (Web/MediaPipe)',
    bestFor: 'Web-only MediaPipe build',
    size: '3.0 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.task',
    webUrl:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.task',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.task,
    preferredBackend: PreferredBackend.gpu,
    maxTokens: 4096,
    supportImage: true,
    supportsFunctionCalls: true,
    isThinking: true,
    maxNumImages: 4,
  ),

  // === Gemma 3 Nano (multimodal, function calls) ===
  GemmaModelPreset(
    id: 'gemma3n-e2b',
    displayName: 'Gemma 3 Nano E2B IT (MediaPipe)',
    bestFor: 'Mobile MediaPipe build — image & text',
    size: '3.1 GB',
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsAuth: true,
    maxTokens: 4096,
    supportImage: true,
    supportsFunctionCalls: false,
    maxNumImages: 4,
    foregroundDownload: true,
  ),
  GemmaModelPreset(
    id: 'gemma3n-e4b',
    displayName: 'Gemma 3 Nano E4B IT (MediaPipe)',
    bestFor: 'Mobile MediaPipe build — larger capacity',
    size: '6.5 GB',
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsAuth: true,
    maxTokens: 4096,
    supportImage: true,
    supportsFunctionCalls: false,
    maxNumImages: 4,
    foregroundDownload: true,
  ),
  GemmaModelPreset(
    id: 'gemma3n-e2b-litertlm',
    displayName: 'Gemma 3 Nano E2B IT',
    bestFor: 'LiteRT-LM — text-first on all platforms',
    size: '3.1 GB',
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm',
    webUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4-Web.litertlm',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
    needsAuth: true,
    maxTokens: 4096,
    supportsFunctionCalls: false,
  ),
  GemmaModelPreset(
    id: 'gemma3n-e4b-litertlm',
    displayName: 'Gemma 3 Nano E4B IT',
    bestFor: 'LiteRT-LM — image, audio & function calls',
    size: '6.5 GB',
    baseUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    webUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4-Web.litertlm',
    desktopUrl:
        'https://huggingface.co/google/gemma-3n-E4B-it-litert-lm/resolve/main/gemma-3n-E4B-it-int4.litertlm',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
    needsAuth: true,
    maxTokens: 4096,
    supportImage: true,
    supportAudio: true,
    supportsFunctionCalls: true,
    maxNumImages: 4,
  ),

  // === Gemma 3 ===
  GemmaModelPreset(
    id: 'gemma3-1b',
    displayName: 'Gemma 3 1B IT',
    bestFor: 'Balanced text — all platforms',
    size: '0.5 GB',
    baseUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    webUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4-web.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsAuth: true,
    maxTokens: 1024,
  ),
  GemmaModelPreset(
    id: 'gemma3-270m',
    displayName: 'Gemma 3 270M IT',
    bestFor: 'Ultra-compact text — fast experiments',
    size: '0.3 GB',
    baseUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task',
    webUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8-web.task',
    desktopUrl:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.litertlm',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsAuth: true,
    maxTokens: 1024,
    supportsFunctionCalls: false,
  ),

  // === Other models ===
  GemmaModelPreset(
    id: 'qwen3-0.6b',
    displayName: 'Qwen3 0.6B',
    bestFor: 'Compact multilingual with thinking',
    size: '586 MB',
    baseUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    preferredBackend: PreferredBackend.cpu,
    maxTokens: 4096,
    supportsFunctionCalls: true,
    isThinking: true,
  ),
  GemmaModelPreset(
    id: 'deepseek-r1-distill',
    displayName: 'DeepSeek R1 Distill Qwen 1.5B',
    bestFor: 'Reasoning with thinking tokens',
    size: '1.7 GB',
    baseUrl:
        'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/deepseek_q8_ekv1280.task',
    modelType: ModelType.deepSeek,
    fileType: ModelFileType.task,
    preferredBackend: PreferredBackend.cpu,
    temperature: 0.6,
    topP: 0.7,
    supportsFunctionCalls: true,
    isThinking: true,
  ),
  GemmaModelPreset(
    id: 'qwen25-1.5b',
    displayName: 'Qwen 2.5 1.5B Instruct',
    bestFor: 'Reliable tool-calling on CPU/GPU',
    size: '1.6 GB',
    baseUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    desktopUrl:
        'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    preferredBackend: PreferredBackend.cpu,
    supportsFunctionCalls: true,
  ),
  GemmaModelPreset(
    id: 'qwen25-0.5b',
    displayName: 'Qwen 2.5 0.5B Instruct',
    bestFor: 'Tiny instruction model (mobile)',
    size: '0.5 GB',
    baseUrl:
        'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.qwen,
    fileType: ModelFileType.task,
    preferredBackend: PreferredBackend.cpu,
    supportsFunctionCalls: true,
  ),
  GemmaModelPreset(
    id: 'smollm-135m',
    displayName: 'SmolLM 135M Instruct',
    bestFor: 'Ultra-small chat (mobile)',
    size: '135 MB',
    baseUrl:
        'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
    modelType: ModelType.general,
    fileType: ModelFileType.task,
    preferredBackend: PreferredBackend.cpu,
    temperature: 0.7,
    topP: 0.9,
  ),
  GemmaModelPreset(
    id: 'fastvlm-0.5b',
    displayName: 'FastVLM 0.5B (Vision)',
    bestFor: 'Vision-language on desktop',
    size: '0.5 GB',
    baseUrl:
        'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
    modelType: ModelType.general,
    fileType: ModelFileType.litertlm,
    maxTokens: 2048,
    supportImage: true,
    maxNumImages: 4,
  ),
  GemmaModelPreset(
    id: 'phi4-mini',
    displayName: 'Phi-4 Mini Instruct',
    bestFor: 'Reasoning & instruction following',
    size: '3.9 GB',
    baseUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.task',
    webUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    desktopUrl:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    modelType: ModelType.general,
    fileType: ModelFileType.task,
    maxTokens: 4096,
    supportsFunctionCalls: true,
  ),

  // === FunctionGemma models ===
  GemmaModelPreset(
    id: 'functiongemma-270m',
    displayName: 'FunctionGemma 270M IT',
    bestFor: 'On-device function calling (LiteRT-LM)',
    size: '284 MB',
    baseUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
    webUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
    desktopUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
    modelType: ModelType.functionGemma,
    fileType: ModelFileType.litertlm,
    supportsFunctionCalls: true,
  ),
  GemmaModelPreset(
    id: 'functiongemma-270m-task',
    displayName: 'FunctionGemma 270M IT (MediaPipe)',
    bestFor: 'On-device function calling (mobile .task)',
    size: '284 MB',
    baseUrl:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.task',
    modelType: ModelType.functionGemma,
    fileType: ModelFileType.task,
    supportsFunctionCalls: true,
  ),
  GemmaModelPreset(
    id: 'functiongemma-demo',
    displayName: 'FunctionGemma Demo',
    bestFor: 'Fine-tuned for the Flutter Gemma demo',
    size: '284 MB',
    baseUrl:
        'https://huggingface.co/sasha-denisov/functiongemma-flutter-gemma-demo/resolve/main/functiongemma-flutter_q8_ekv1024.task',
    modelType: ModelType.functionGemma,
    fileType: ModelFileType.task,
    supportsFunctionCalls: true,
  ),
];

GemmaModelPreset? findGemmaPreset(String id) {
  try {
    return gemmaModelPresets.firstWhere((p) => p.id == id);
  } on StateError {
    return null;
  }
}
