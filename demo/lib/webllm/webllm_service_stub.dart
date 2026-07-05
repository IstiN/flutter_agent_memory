/// Stub WebLLM types for non-web platforms (VM tests).
///
/// The real implementation lives in [webllm_service_web.dart] and is
/// conditionally exported by [webllm_service.dart] when `dart.library.js_interop`
/// is available.
class WebLlmModelPreset {
  final String id;
  final String displayName;
  final String family;
  final String size;
  final int? defaultContextWindow;
  final double temperature;
  final double topP;

  const WebLlmModelPreset({
    required this.id,
    required this.displayName,
    required this.family,
    required this.size,
    this.defaultContextWindow,
    this.temperature = 0.7,
    this.topP = 0.9,
  });
}

class WebLlmService {
  Stream<Never> get progress => const Stream<Never>.empty();

  Future<void> loadModel(
    WebLlmModelPreset preset, {
    int? contextWindowSize,
  }) async {}

  Future<String> chat({
    required List<({String role, String content})> messages,
    required bool stream,
    int? maxTokens,
  }) async =>
      throw UnsupportedError('WebLLM is only supported on the web.');

  Future<void> interrupt() async {}
  Future<void> dispose() async {}
}

const List<WebLlmModelPreset> webLlmModelPresets = [
  WebLlmModelPreset(
    id: 'SmolLM2-135M-Instruct-q0f16-MLC',
    displayName: 'SmolLM2 135M',
    family: 'smollm',
    size: '~270 MB',
    defaultContextWindow: 2048,
    temperature: 1.0,
    topP: 1.0,
  ),
];

WebLlmModelPreset? findWebLlmPreset(String id) {
  try {
    return webLlmModelPresets.firstWhere((p) => p.id == id);
  } on StateError {
    return null;
  }
}
