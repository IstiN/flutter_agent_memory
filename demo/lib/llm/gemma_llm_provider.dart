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

  @override
  Future<String> chat(String prompt, {String? model}) => _run([
    LlmMessage(role: 'user', content: prompt),
  ]);

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) =>
      _run(messages);

  void _log(String message) {
    // ignore: avoid_print
    print('[GemmaLlmProvider] $message');
  }

  Future<String> _run(List<LlmMessage> messages) async {
    _log('_run start: ${messages.length} message(s), '
        'preset=${_preset.id}, maxTokens=${_preset.maxTokens}, '
        'maxOutputTokens=${_preset.maxOutputTokens}');
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      _log('message $i: role=${msg.role}, textLength=${msg.content.length}, '
          'text=${msg.content.length > 500 ? '${msg.content.substring(0, 500)}...' : msg.content}');
    }

    final model = await _service.loadModel(_preset);
    _log('model loaded, creating session...');
    final session = await model.createSession(
      temperature: _preset.temperature,
      topK: _preset.topK,
      topP: _preset.topP,
      maxOutputTokens: _preset.maxOutputTokens,
    );
    _log('session created');
    try {
      for (final msg in messages) {
        final gemmaMsg = _toGemmaMessage(msg);
        _log('addQueryChunk: role=${msg.role}, textLength=${msg.content.length}');
        await session.addQueryChunk(gemmaMsg);
      }
      _log('waiting for response (streaming)...');

      // Prefill/decode models (Gemma 4, FunctionGemma litertlm) do not support
      // the synchronous getResponse() path and return an empty/cancelled result.
      // Collect the async token stream instead.
      final buffer = StringBuffer();
      await for (final token in session.getResponseAsync()) {
        buffer.write(token);
      }
      final response = buffer.toString();
      _log('response received, length=${response.length}, '
          'preview=${response.length > 500 ? '${response.substring(0, 500)}...' : response}');
      return response;
    } catch (e, s) {
      _log('inference error: $e\n$s');
      rethrow;
    } finally {
      _log('closing session');
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
