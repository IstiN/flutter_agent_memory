import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

import 'webllm_js_interop.dart';

/// Preset describing a WebLLM model available through `@mlc-ai/web-llm`.
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

/// Service that owns the `@mlc-ai/web-llm` MLCEngine singleton.
///
/// Mirrors [GemmaService]: initializes the engine on first use, reloads the
/// model when the preset changes, and exposes a simple chat interface.
class WebLlmService {
  WebLlmEngine? _engine;
  String? _loadedModelId;

  final _progressController = StreamController<WebLlmProgressReport>.broadcast();
  Stream<WebLlmProgressReport> get progress => _progressController.stream;

  void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[WebLlmService] $message');
    }
  }

  /// Ensure the engine is created. The actual model weights are loaded in
  /// [loadModel].
  Future<WebLlmEngine> _ensureEngine() async {
    if (_engine != null) return _engine!;
    _log('creating MLCEngine');
    final config = WebLlmEngineConfig(
      appConfig: prebuiltAppConfig,
      logLevel: kDebugMode ? 'INFO'.toJS : 'WARN'.toJS,
      useWebWorker: false.toJS,
    );
    final engine = _engine = WebLlmEngine(config);
    engine.setInitProgressCallback(
      ((JSObject report) {
        _progressController.add(WebLlmProgressReport(report));
      }).toJS,
    );
    return engine;
  }

  /// Load (or reload) the requested model. WebLLM caches weights in the
  /// browser, so subsequent reloads of the same model are fast.
  Future<void> loadModel(
    WebLlmModelPreset preset, {
    int? contextWindowSize,
  }) async {
    final engine = await _ensureEngine();
    final modelId = preset.id;
    if (_loadedModelId == modelId) {
      _log('model $modelId already loaded');
      return;
    }
    _log('loading model $modelId');
    final chatConfig = {
      'context_window_size': contextWindowSize,
      'temperature': preset.temperature,
      'top_p': preset.topP,
    }.jsify();
    await engine.reload(modelId.toJS, chatConfig).toDart;
    _loadedModelId = modelId;
    _log('model $modelId loaded');
  }

  /// Run a chat completion. [messages] must alternate user/assistant roles.
  Future<String> chat({
    required List<({String role, String content})> messages,
    required bool stream,
    int? maxTokens,
  }) async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('No model loaded. Call loadModel() first.');
    }
    final jsMessages = messages
        .map(
          (m) => {'role': m.role, 'content': m.content}.jsify() as JSObject,
        )
        .toList()
        .toJS;
    final request = {
      'stream': stream,
      'messages': jsMessages,
      'max_tokens': ?maxTokens,
    }.jsify() as JSObject;

    if (stream) {
      final asyncIterable = await engine.chatCompletion(request).toDart as JSObject;
      final chunks = await webllmStreamToArray(asyncIterable).toDart;
      final buffer = StringBuffer();
      for (final chunk in chunks.toDart) {
        final choices = chunk.getProperty<JSArray?>('choices'.toJS);
        if (choices == null || choices.length == 0) continue;
        final first = choices.toDart.first as JSObject;
        final delta = first.getProperty<JSObject?>('delta'.toJS);
        final content = delta?.getProperty<JSString?>('content'.toJS);
        if (content != null) {
          buffer.write(content.toDart);
        }
      }
      return buffer.toString();
    }

    final response = await engine.chatCompletion(request).toDart as JSObject;
    final choices = response.getProperty<JSArray>('choices'.toJS);
    final first = choices.toDart.first as JSObject;
    final message = first.getProperty<JSObject>('message'.toJS);
    final content = message.getProperty<JSString>('content'.toJS);
    return content.toDart;
  }

  Future<void> interrupt() async {
    if (_engine != null) {
      await _engine!.interruptGenerate().toDart;
    }
  }

  Future<void> dispose() async {
    await _progressController.close();
    // WebLLM has no explicit dispose API; drop the reference so the engine
    // can be garbage collected.
    _engine = null;
    _loadedModelId = null;
  }
}

/// Available WebLLM presets for the demo. Focus on small models that run
/// comfortably in a browser tab.
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
  WebLlmModelPreset(
    id: 'SmolLM2-360M-Instruct-q0f16-MLC',
    displayName: 'SmolLM2 360M',
    family: 'smollm',
    size: '~720 MB',
    defaultContextWindow: 2048,
    temperature: 1.0,
    topP: 1.0,
  ),
  WebLlmModelPreset(
    id: 'Qwen2.5-0.5B-Instruct-q0f16-MLC',
    displayName: 'Qwen2.5 0.5B',
    family: 'qwen',
    size: '~1 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),
  WebLlmModelPreset(
    id: 'Qwen2.5-1.5B-Instruct-q4f16_1-MLC',
    displayName: 'Qwen2.5 1.5B',
    family: 'qwen',
    size: '~1 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),
  WebLlmModelPreset(
    id: 'Phi-3.5-mini-instruct-q4f16_1-MLC',
    displayName: 'Phi-3.5 mini',
    family: 'phi',
    size: '~2.3 GB',
    defaultContextWindow: 2048,
    temperature: 1.0,
    topP: 1.0,
  ),
  WebLlmModelPreset(
    id: 'gemma-2-2b-it-q4f16_1-MLC',
    displayName: 'Gemma 2 2B',
    family: 'gemma',
    size: '~1.6 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.95,
  ),
  WebLlmModelPreset(
    id: 'Llama-3.2-1B-Instruct-q4f16_1-MLC',
    displayName: 'Llama 3.2 1B',
    family: 'llama',
    size: '~770 MB',
    defaultContextWindow: 2048,
    temperature: 0.6,
    topP: 0.9,
  ),
  WebLlmModelPreset(
    id: 'Llama-3.2-3B-Instruct-q4f16_1-MLC',
    displayName: 'Llama 3.2 3B',
    family: 'llama',
    size: '~1.9 GB',
    defaultContextWindow: 2048,
    temperature: 0.6,
    topP: 0.9,
  ),
];

WebLlmModelPreset? findWebLlmPreset(String id) {
  try {
    return webLlmModelPresets.firstWhere((p) => p.id == id);
  } on StateError {
    return null;
  }
}
