import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../services/gemma_model_presets.dart';
import '../services/gemma_service.dart';

/// [LlmProvider] adapter that runs inference through Flutter Gemma.
class GemmaLlmProvider implements LlmProvider {
  final GemmaService _service;
  final GemmaModelPreset _preset;

  GemmaLlmProvider(this._service, this._preset);

  @override
  String get defaultModel => _preset.id;

  /// Default timeout for on-device Gemma inference in the demo. WebGPU/WASM
  /// models can spend 30–90 s on first-run shader compilation, so keep this
  /// generous but not infinite.
  static const _defaultTimeout = Duration(seconds: 120);

  Future<String> _runWithTimeout(
    Future<String> Function() fn, {
    Duration? timeout,
  }) async {
    final effective = timeout ?? _defaultTimeout;
    try {
      return await fn().timeout(effective);
    } on TimeoutException {
      _log('inference timed out after ${effective.inSeconds}s');
      throw TimeoutException(
        'Gemma inference did not complete within ${effective.inSeconds}s. '
        'Large web models often need one-time WebGPU shader compilation; '
        'try again after keeping the page open for a minute.',
      );
    }
  }

  @override
  Future<String> chat(String prompt, {String? model}) => _runWithTimeout(
    () => _run([
      LlmMessage(role: 'user', content: prompt),
    ]),
  );

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) =>
      _runWithTimeout(() => _run(messages));

  void _log(String message) {
    // ignore: avoid_print
    print('[GemmaLlmProvider] $message');
  }

  Future<String> _run(List<LlmMessage> messages) async {
    final sw = Stopwatch()..start();
    _log('_run start: ${messages.length} message(s), '
        'preset=${_preset.id}, maxTokens=${_preset.maxTokens}, '
        'maxOutputTokens=${_preset.maxOutputTokens}');
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      _log('message $i: role=${msg.role}, textLength=${msg.content.length}, '
          'text=${msg.content.length > 500 ? '${msg.content.substring(0, 500)}...' : msg.content}');
    }

    _log('[timing] loading model...');
    final model = await _service.loadModel(_preset);
    _log('[timing] model loaded in ${sw.elapsedMilliseconds}ms, creating session...');
    final session = await model.createSession(
      temperature: _preset.temperature,
      topK: _preset.topK,
      topP: _preset.topP,
      maxOutputTokens: _preset.maxOutputTokens,
    );
    _log('[timing] session created in ${sw.elapsedMilliseconds}ms');
    try {
      for (final msg in messages) {
        final gemmaMsg = _toGemmaMessage(msg);
        _log('addQueryChunk: role=${msg.role}, textLength=${msg.content.length}');
        await session.addQueryChunk(gemmaMsg);
      }
      _log('[timing] waiting for response (streaming) at ${sw.elapsedMilliseconds}ms...');

      // Try the synchronous getResponse() first — MediaPipe web returns the full
      // response through the Future, while getResponseAsync() may fire an empty
      // stream for some model/preset combinations.
      _log('[debug] trying getResponse()...');
      final syncResponse = await session.getResponse();
      _log('[debug] getResponse() returned length=${syncResponse.length}, '
          'preview="${syncResponse.length > 200 ? '${syncResponse.substring(0, 200)}...' : syncResponse}"');
      if (syncResponse.isNotEmpty) {
        _log('[timing] sync response received in ${sw.elapsedMilliseconds}ms');
        return syncResponse;
      }

      _log('[debug] sync response empty, falling back to getResponseAsync()...');
      final buffer = StringBuffer();
      await for (final token in session.getResponseAsync()) {
        buffer.write(token);
      }
      final response = buffer.toString();
      _log('[timing] async response received in ${sw.elapsedMilliseconds}ms, '
          'length=${response.length}, '
          'preview=${response.length > 500 ? '${response.substring(0, 500)}...' : response}');
      return response;
    } catch (e, s) {
      _log('inference error after ${sw.elapsedMilliseconds}ms: $e\n$s');
      rethrow;
    } finally {
      _log('[timing] closing session at ${sw.elapsedMilliseconds}ms');
      await session.close();
    }
  }

  Message _toGemmaMessage(LlmMessage msg) {
    final isUser = msg.role == 'user';
    final images = msg.images;
    if (images != null && images.isNotEmpty) {
      final bytes = _decodeBase64Image(images.first);
      return Message.withImage(
        text: msg.content,
        imageBytes: bytes,
        isUser: isUser,
      );
    }
    return Message.text(text: msg.content, isUser: isUser);
  }

  Uint8List _decodeBase64Image(String dataUrl) {
    final base64Part = dataUrl.contains(',') ? dataUrl.split(',')[1] : dataUrl;
    return base64Decode(base64Part);
  }
}
