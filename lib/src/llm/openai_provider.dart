import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'llm_message.dart';
import 'llm_provider.dart';

/// OpenAI-compatible chat provider.
///
/// Works with the official OpenAI API as well as any API that copies the
/// `/chat/completions` request/response shape.
class OpenAiProvider implements LlmProvider {
  final String apiKey;
  final String baseUrl;
  @override
  final String defaultModel;
  final int maxTokens;
  final double temperature;
  final String maxTokensParamName;
  final Map<String, String> customHeaders;
  final http.Client _client;

  OpenAiProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1/chat/completions',
    required this.defaultModel,
    this.maxTokens = 4096,
    this.temperature = -1,
    this.maxTokensParamName = 'max_completion_tokens',
    this.customHeaders = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<String> chat(String prompt, {String? model}) =>
      chatMessages([LlmMessage(role: 'user', content: prompt)], model: model);

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async {
    final payload = _buildPayload(messages, model ?? defaultModel);
    final response = await _client.post(
      Uri.parse(baseUrl),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.authorizationHeader: 'Bearer $apiKey',
        ...customHeaders,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'OpenAI request failed: ${response.statusCode} ${response.body}',
        uri: Uri.parse(baseUrl),
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _extractContent(json);
  }

  Map<String, dynamic> _buildPayload(List<LlmMessage> messages, String model) {
    final payload = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (temperature >= 0) {
      payload['temperature'] = temperature;
    }
    if (maxTokensParamName.isNotEmpty) {
      payload[maxTokensParamName] = maxTokens;
    }
    return payload;
  }

  String _extractContent(Map<String, dynamic> json) {
    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final message = choices.first['message'] as Map<String, dynamic>?;
      if (message != null) {
        final content = message['content'];
        if (content is String) return content;
      }
    }
    if (json.containsKey('error')) {
      return jsonEncode(json);
    }
    return '';
  }
}
