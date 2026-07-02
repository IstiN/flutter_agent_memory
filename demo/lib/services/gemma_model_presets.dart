import 'package:flutter_gemma/flutter_gemma.dart';

/// Curated on-device model presets for the Flutter Gemma provider.
///
/// These mirror the model gallery on fluttergemma.dev, filtered to formats
/// that work on the web (MediaPipe `.task` and LiteRT-LM `.litertlm`).
class GemmaModelPreset {
  final String id;
  final String displayName;
  final String bestFor;
  final String size;
  final String url;
  final ModelType modelType;
  final ModelFileType fileType;
  final PreferredBackend preferredBackend;
  final bool needsAuth;
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;

  const GemmaModelPreset({
    required this.id,
    required this.displayName,
    required this.bestFor,
    required this.size,
    required this.url,
    required this.modelType,
    required this.fileType,
    this.preferredBackend = PreferredBackend.gpu,
    this.needsAuth = false,
    this.maxTokens = 1024,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.95,
  });

  /// Unique filename used as the installed-model identity.
  String get filename {
    return url.split('/').last;
  }
}

const List<GemmaModelPreset> gemmaModelPresets = [
  GemmaModelPreset(
    id: 'gemma3-270m',
    displayName: 'Gemma 3 270M IT',
    bestFor: 'Ultra-compact text — fast experiments',
    size: '0.3 GB',
    url:
        'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8-web.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsAuth: true,
    maxTokens: 1024,
  ),
  GemmaModelPreset(
    id: 'gemma3-1b',
    displayName: 'Gemma 3 1B IT',
    bestFor: 'Balanced text — all platforms',
    size: '0.5 GB',
    url:
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4-web.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    needsAuth: true,
    maxTokens: 1024,
  ),
  GemmaModelPreset(
    id: 'functiongemma-270m',
    displayName: 'FunctionGemma 270M IT',
    bestFor: 'On-device function calling',
    size: '284 MB',
    url:
        'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
    modelType: ModelType.functionGemma,
    fileType: ModelFileType.litertlm,
    maxTokens: 1024,
  ),
  GemmaModelPreset(
    id: 'qwen3-0.6b',
    displayName: 'Qwen3 0.6B',
    bestFor: 'Compact multilingual with thinking',
    size: '586 MB',
    url:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    modelType: ModelType.qwen3,
    fileType: ModelFileType.litertlm,
    preferredBackend: PreferredBackend.cpu,
    maxTokens: 4096,
  ),
  GemmaModelPreset(
    id: 'phi4-mini',
    displayName: 'Phi-4 Mini Instruct',
    bestFor: 'Reasoning & instruction following',
    size: '3.9 GB',
    url:
        'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
    modelType: ModelType.general,
    fileType: ModelFileType.litertlm,
    maxTokens: 4096,
  ),
  GemmaModelPreset(
    id: 'gemma4-e2b',
    displayName: 'Gemma 4 E2B IT',
    bestFor: 'Next-gen multimodal — text, image & audio',
    size: '2.0 GB',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.task',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.task,
    maxTokens: 4096,
  ),
  GemmaModelPreset(
    id: 'gemma4-e4b',
    displayName: 'Gemma 4 E4B IT',
    bestFor: 'Next-gen multimodal — higher capacity',
    size: '3.0 GB',
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it-web.task',
    modelType: ModelType.gemma4,
    fileType: ModelFileType.task,
    maxTokens: 4096,
  ),
];

GemmaModelPreset? findGemmaPreset(String id) {
  try {
    return gemmaModelPresets.firstWhere((p) => p.id == id);
  } on StateError {
    return null;
  }
}
