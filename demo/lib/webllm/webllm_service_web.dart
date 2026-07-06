import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

import 'webllm_js_interop.dart';

/// Converts a JS AsyncIterable (returned by WebLLM's streaming
/// `chatCompletion`) into a Dart [Stream] by reading it with a
/// [ReadableStreamDefaultReader].
Stream<JSObject> _asyncIterableToStream(JSObject asyncIterable) {
  final controller = StreamController<JSObject>();

  // Get the reader: asyncIterable.getReader()
  final reader = asyncIterable.callMethod<JSObject>(
    'getReader'.toJS,
    <JSAny?>[].toJS,
  );

  Future<void> readNext() async {
    try {
      while (!controller.isClosed) {
        final result = await reader
            .callMethod<JSPromise<JSObject>>('read'.toJS, <JSAny?>[].toJS)
            .toDart;
        final done = result.getProperty<JSBoolean?>('done'.toJS)?.toDart ?? false;
        if (done) {
          controller.close();
          return;
        }
        final value = result.getProperty<JSObject?>('value'.toJS);
        if (value != null) {
          controller.add(value);
        }
      }
    } catch (e, st) {
      controller.addError(e, st);
    }
  }

  controller.onCancel = () async {
    try {
      await reader
          .callMethod<JSPromise<JSAny?>>('cancel'.toJS, <JSAny?>[].toJS)
          .toDart;
    } catch (_) {}
    await controller.close();
  };

  readNext();
  return controller.stream;
}

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
  bool _disposed = false;

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
        if (!_disposed) _progressController.add(report as WebLlmProgressReport);
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
    try {
      await engine.reload(modelId.toJS, chatConfig).toDart;
      _loadedModelId = modelId;
      _log('model $modelId loaded');
    } catch (e) {
      // If reload is aborted (e.g. user pressed Stop while weights were
      // downloading), reset the loaded-model state so the next run retries
      // the full load instead of assuming the model is ready. Also drop the
      // engine instance because an aborted MLCEngine can be left in a bad
      // state where it reports "ready" but cannot run inference.
      _loadedModelId = null;
      _engine = null;
      _log('model $modelId reload failed, reset engine state: $e');
      rethrow;
    }
  }

  /// Run a chat completion. [messages] must alternate user/assistant roles.
  Future<String> chat({
    required List<({String role, String content})> messages,
    required bool stream,
    int? maxTokens,
  }) async {
    if (!stream) {
      return _chatNonStream(messages: messages, maxTokens: maxTokens);
    }
    final buffer = StringBuffer();
    final cancel = await chatStream(
      messages: messages,
      maxTokens: maxTokens,
      onChunk: (chunk) => buffer.write(chunk),
    );
    try {
      cancel();
    } catch (_) {}
    return buffer.toString();
  }

  Future<String> _chatNonStream({
    required List<({String role, String content})> messages,
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
      'stream': false,
      'messages': jsMessages,
      'max_tokens': maxTokens,
      'stop': ['<|endoftext|>', '<|im_end|>', '</s>'].jsify(),
    }.jsify() as JSObject;

    _log('chatCompletion request stream=false maxTokens=$maxTokens messages=${messages.length}');
    final response = await engine.chatCompletion(request).toDart as JSObject;
    final choices = response.getProperty<JSArray>('choices'.toJS);
    final first = choices.toDart.first as JSObject;
    final message = first.getProperty<JSObject>('message'.toJS);
    final content = message.getProperty<JSString>('content'.toJS);
    return content.toDart;
  }

  /// Streams a chat completion. Returns a cancel function that stops generation.
  Future<void Function()> chatStream({
    required List<({String role, String content})> messages,
    required void Function(String chunk) onChunk,
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
      'stream': true,
      'messages': jsMessages,
      'max_tokens': maxTokens,
      'stop': ['<|endoftext|>', '<|im_end|>', '</s>'].jsify(),
    }.jsify() as JSObject;

    _log('chatCompletion request stream=true maxTokens=$maxTokens messages=${messages.length}');
    final asyncIterable = await engine.chatCompletion(request).toDart as JSObject;

    // WebLLM returns a standard JS ReadableStream for streaming chat completions.
    // Read it chunk-by-chunk instead of trying to call Symbol.asyncIterator
    // through dart2js, which produced "a[b] is not a function" in release builds.
    final stream = _asyncIterableToStream(asyncIterable).map(
      (value) => _extractChunkContent(value),
    );

    var tokens = 0;
    var done = false;

    void cancel() {
      if (done) return;
      done = true;
      _log('stream cancelled by caller');
    }

    Future<void> run() async {
      try {
        await for (final content in stream) {
          if (done) break;
          if (content != null && content.isNotEmpty) {
            tokens += 1;
            _log('chunk tokens=$tokens content="${content.substring(0, content.length > 80 ? 80 : content.length).replaceAll('\n', '\\n')}"');
            onChunk(content);
          }
        }
      } catch (e) {
        _log('stream error: $e');
      } finally {
        done = true;
        _log('stream done, tokens=$tokens');
      }
    }

    run();
    return cancel;
  }

  String? _extractChunkContent(JSObject value) {
    try {
      final choices = value.getProperty<JSArray?>('choices'.toJS);
      if (choices == null) return null;
      final first = choices.toDart.firstOrNull as JSObject?;
      if (first == null) return null;
      final delta = first.getProperty<JSObject?>('delta'.toJS);
      if (delta == null) return null;
      final content = delta.getProperty<JSString?>('content'.toJS);
      return content?.toDart;
    } catch (_) {
      return null;
    }
  }

  Future<void> interrupt() async {
    if (_engine != null) {
      await _engine!.interruptGenerate().toDart;
    }
  }

  Future<bool> isModelCached(String modelId) async {
    try {
      final cached = await webllmIsModelCached(modelId.toJS).toDart as JSBoolean?;
      return cached?.toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  /// WebLLM caches weights in the browser; this exposes cache visibility via a
  /// tiny JS helper that reports CacheStorage entries matching the model id.
  Future<double?> modelDownloadProgress(String modelId) async {
    try {
      final progress = await webllmModelProgress(modelId.toJS).toDart;
      return progress?.toDartDouble;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the model from WebLLM's cache by invalidating CacheStorage
  /// entries whose URL contains the model id.
  Future<void> deleteModel(String modelId) async {
    _log('deleting cached model $modelId');
    await webllmDeleteModel(modelId.toJS).toDart;
    if (_loadedModelId == modelId) {
      _loadedModelId = null;
      _engine = null;
    }
    _log('deleted cached model $modelId');
  }

  Future<void> dispose() async {
    _disposed = true;
    await _progressController.close();
    // WebLLM has no explicit dispose API; drop the reference so the engine
    // can be garbage collected.
    _engine = null;
    _loadedModelId = null;
  }
}

/// Available WebLLM presets for the demo.
///
/// Sources are `@mlc-ai/web-llm` prebuilt models hosted on HuggingFace
/// (`https://huggingface.co/mlc-ai/...`) with model libraries served from
/// `https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/`.
/// Sizes are approximate downloaded weight sizes.
const List<WebLlmModelPreset> webLlmModelPresets = [
  // === SmolLM2 ===
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
    id: 'SmolLM2-1.7B-Instruct-q4f16_1-MLC',
    displayName: 'SmolLM2 1.7B',
    family: 'smollm',
    size: '~1.8 GB',
    defaultContextWindow: 2048,
    temperature: 1.0,
    topP: 1.0,
  ),

  // === Qwen 2.5 ===
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
    id: 'Qwen2.5-3B-Instruct-q4f16_1-MLC',
    displayName: 'Qwen2.5 3B',
    family: 'qwen',
    size: '~1.9 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),
  WebLlmModelPreset(
    id: 'Qwen2.5-7B-Instruct-q4f16_1-MLC',
    displayName: 'Qwen2.5 7B',
    family: 'qwen',
    size: '~4.2 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),

  // === Qwen 3 ===
  WebLlmModelPreset(
    id: 'Qwen3-0.6B-q4f16_1-MLC',
    displayName: 'Qwen3 0.6B',
    family: 'qwen',
    size: '~750 MB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),
  WebLlmModelPreset(
    id: 'Qwen3-1.7B-q4f16_1-MLC',
    displayName: 'Qwen3 1.7B',
    family: 'qwen',
    size: '~1.4 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),
  WebLlmModelPreset(
    id: 'Qwen3-4B-q4f16_1-MLC',
    displayName: 'Qwen3 4B',
    family: 'qwen',
    size: '~2.8 GB',
    defaultContextWindow: 2048,
    temperature: 0.7,
    topP: 0.8,
  ),

  // === Phi ===
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
    id: 'Phi-3.5-mini-instruct-q4f16_1-MLC-1k',
    displayName: 'Phi-3.5 mini (1k)',
    family: 'phi',
    size: '~1.6 GB',
    defaultContextWindow: 1024,
    temperature: 1.0,
    topP: 1.0,
  ),
  WebLlmModelPreset(
    id: 'Phi-4-mini-instruct-q4f16_1-MLC',
    displayName: 'Phi-4 mini',
    family: 'phi',
    size: '~2.1 GB',
    defaultContextWindow: 2048,
    temperature: 1.0,
    topP: 1.0,
  ),

  // === Gemma 2 ===
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
    id: 'gemma-2-2b-it-q4f16_1-MLC-1k',
    displayName: 'Gemma 2 2B (1k)',
    family: 'gemma',
    size: '~1.2 GB',
    defaultContextWindow: 1024,
    temperature: 0.7,
    topP: 0.95,
  ),

  // === Llama 3.2 ===
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
    id: 'Llama-3.2-1B-Instruct-q4f32_1-MLC',
    displayName: 'Llama 3.2 1B (f32)',
    family: 'llama',
    size: '~1.4 GB',
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

  // === Llama 3.1 ===
  WebLlmModelPreset(
    id: 'Llama-3.1-8B-Instruct-q4f16_1-MLC-1k',
    displayName: 'Llama 3.1 8B (1k)',
    family: 'llama',
    size: '~4.3 GB',
    defaultContextWindow: 1024,
    temperature: 0.6,
    topP: 0.9,
  ),
  WebLlmModelPreset(
    id: 'Llama-3.1-8B-Instruct-q4f16_1-MLC',
    displayName: 'Llama 3.1 8B',
    family: 'llama',
    size: '~4.6 GB',
    defaultContextWindow: 2048,
    temperature: 0.6,
    topP: 0.9,
  ),

  // === Hermes / tool-calling variants ===
  WebLlmModelPreset(
    id: 'Hermes-3-Llama-3.2-3B-q4f16_1-MLC',
    displayName: 'Hermes 3 Llama 3.2 3B',
    family: 'llama',
    size: '~1.9 GB',
    defaultContextWindow: 2048,
    temperature: 0.6,
    topP: 0.9,
  ),
  WebLlmModelPreset(
    id: 'Hermes-3-Llama-3.1-8B-q4f16_1-MLC',
    displayName: 'Hermes 3 Llama 3.1 8B',
    family: 'llama',
    size: '~4.5 GB',
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
