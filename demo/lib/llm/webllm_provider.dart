import 'dart:async';

import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/settings_service.dart';
import '../webllm/webllm_service.dart';

/// [LlmProvider] adapter that runs inference through `@mlc-ai/web-llm`.
class WebLlmProvider implements LlmProvider {
  final WebLlmService _service;
  final WebLlmModelPreset _preset;
  final SettingsService _settings;

  WebLlmProvider(this._service, this._preset, this._settings);

  @override
  String get defaultModel => _preset.id;

  /// WebLLM models compile shaders on first run; give them a generous timeout.
  static const _defaultTimeout = Duration(seconds: 180);

  Future<String> _runWithTimeout(
    Future<String> Function() fn, {
    Duration? timeout,
    void Function()? onCancel,
  }) async {
    final effective = timeout ?? _defaultTimeout;
    try {
      return await fn().timeout(effective);
    } on TimeoutException {
      _log('inference timed out after ${effective.inSeconds}s');
      onCancel?.call();
      throw TimeoutException(
        'WebLLM inference did not complete within ${effective.inSeconds}s. '
        'First run compiles WebGPU shaders; try again after keeping the page open.',
      );
    }
  }

  @override
  Future<String> chat(String prompt, {String? model, void Function()? onCancel}) => _runWithTimeout(
    () => _run([(role: 'user', content: prompt)]),
    onCancel: onCancel,
  );

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async {
    return _runWithTimeout(
      () => _run(messages.map(_toWebLlmMessage).toList()),
      onCancel: onCancel,
    );
  }

  @override
  Stream<String> chatStream(
    String prompt, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield* _streamRun([(role: 'user', content: prompt)], onCancel: onCancel);
  }

  @override
  Stream<String> chatMessagesStream(
    List<LlmMessage> messages, {
    String? model,
    void Function()? onCancel,
  }) async* {
    yield* _streamRun(messages.map(_toWebLlmMessage).toList(), onCancel: onCancel);
  }

  @override
  Future<void> cancel() async {
    _log('cancel requested');
    await _service.interrupt();
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[WebLlmProvider] $message');
  }

  Stream<String> _streamRun(
    List<({String role, String content})> messages, {
    void Function()? onCancel,
  }) async* {
    final sw = Stopwatch()..start();
    _log('_streamRun start: ${messages.length} message(s), preset=${_preset.id}, '
        'contextWindow=${_settings.webLlmContextWindowSize}, '
        'maxOutputTokens=${_settings.webLlmMaxOutputTokens}');

    await _service.loadModel(
      _preset,
      contextWindowSize: _settings.webLlmContextWindowSize,
    );
    _log('model ready in ${sw.elapsedMilliseconds}ms');

    final effectiveMaxTokens = _settings.webLlmMaxOutputTokens.clamp(16, 2048);
    _log('calling chatStream with maxTokens=$effectiveMaxTokens');

    final controller = StreamController<String>();
    void Function()? cancelFn;
    try {
      cancelFn = await _service.chatStream(
        messages: messages,
        maxTokens: effectiveMaxTokens,
        onChunk: controller.add,
      );
      await for (final chunk in controller.stream) {
        yield chunk;
      }
      _log('stream completed in ${sw.elapsedMilliseconds}ms');
    } on TimeoutException {
      _log('stream timed out after ${sw.elapsedMilliseconds}ms');
      onCancel?.call();
      cancelFn?.call();
      rethrow;
    } catch (e, s) {
      _log('stream error after ${sw.elapsedMilliseconds}ms: $e\n$s');
      rethrow;
    } finally {
      _log('stream finally after ${sw.elapsedMilliseconds}ms');
      cancelFn?.call();
      await controller.close();
    }
  }

  Future<String> _run(List<({String role, String content})> messages) async {
    final sw = Stopwatch()..start();
    _log('_run start: ${messages.length} message(s), preset=${_preset.id}, '
        'contextWindow=${_settings.webLlmContextWindowSize}, '
        'maxOutputTokens=${_settings.webLlmMaxOutputTokens}');

    await _service.loadModel(
      _preset,
      contextWindowSize: _settings.webLlmContextWindowSize,
    );
    _log('model ready in ${sw.elapsedMilliseconds}ms');

    try {
      final effectiveMaxTokens = _settings.webLlmMaxOutputTokens.clamp(16, 2048);
      _log('calling chat with maxTokens=$effectiveMaxTokens');
      final response = await _service.chat(
        messages: messages,
        stream: false,
        maxTokens: effectiveMaxTokens,
      );
      _log('response received in ${sw.elapsedMilliseconds}ms, '
          'length=${response.length}, '
          'preview=${response.length > 500 ? '${response.substring(0, 500)}...' : response}');
      return response;
    } catch (e, s) {
      _log('inference error after ${sw.elapsedMilliseconds}ms: $e\n$s');
      rethrow;
    }
  }

  ({String role, String content}) _toWebLlmMessage(LlmMessage msg) {
    final role = switch (msg.role) {
      'system' => 'system',
      'assistant' => 'assistant',
      _ => 'user',
    };
    return (role: role, content: msg.content);
  }
}
