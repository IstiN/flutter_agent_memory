import 'dart:convert';
import 'dart:developer' as dev;
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

  Future<String> _run(List<LlmMessage> messages) async {
    dev.log('[GemmaLlmProvider] _run start: ${messages.length} message(s), '
        'preset=${_preset.id}, maxTokens=${_preset.maxTokens}');
    final model = await _service.loadModel(_preset);
    dev.log('[GemmaLlmProvider] model loaded, creating session...');
    final session = await model.createSession(
      temperature: _preset.temperature,
      topK: _preset.topK,
      topP: _preset.topP,
      maxOutputTokens: _preset.maxTokens,
    );
    dev.log('[GemmaLlmProvider] session created');
    try {
      for (final msg in messages) {
        final gemmaMsg = _toGemmaMessage(msg);
        dev.log('[GemmaLlmProvider] addQueryChunk: role=${msg.role}, '
            'textLength=${msg.content.length}');
        await session.addQueryChunk(gemmaMsg);
      }
      dev.log('[GemmaLlmProvider] waiting for response...');
      final response = await session.getResponse();
      dev.log('[GemmaLlmProvider] response received, length=${response.length}, '
          'preview=${response.length > 200 ? response.substring(0, 200) : response}');
      return response;
    } catch (e, s) {
      dev.log('[GemmaLlmProvider] inference error: $e', stackTrace: s);
      rethrow;
    } finally {
      dev.log('[GemmaLlmProvider] closing session');
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
