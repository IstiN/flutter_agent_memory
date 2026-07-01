import 'package:flutter_agent_memory/src/agents/kb_analysis_agent.dart';
import 'package:flutter_agent_memory/src/llm/llm_message.dart';
import 'package:flutter_agent_memory/src/llm/llm_provider.dart';
import 'package:flutter_agent_memory/src/models/kb_context.dart';
import 'package:test/test.dart';

class _VisionFakeProvider implements LlmProvider {
  List<LlmMessage>? capturedMessages;

  @override
  String get defaultModel => 'vision-model';

  @override
  Future<String> chat(String prompt, {String? model}) async =>
      '{"questions":[],"answers":[],"notes":[]}';

  @override
  Future<String> chatMessages(
    List<LlmMessage> messages, {
    String? model,
  }) async {
    capturedMessages = messages;
    return '{"questions":[],"answers":[],"notes":[]}';
  }
}

void main() {
  test('sends images when provided', () async {
    final provider = _VisionFakeProvider();
    final agent = KBAnalysisAgent(provider);

    await agent.analyze(
      'Describe the image.',
      KBContext(),
      images: ['data:image/png;base64,abc123'],
    );

    expect(provider.capturedMessages, isNotNull);
    expect(provider.capturedMessages!.length, 1); // single user message with prompt and images
    final userMessage = provider.capturedMessages!.single;
    expect(userMessage.images, hasLength(1));
  });
}
