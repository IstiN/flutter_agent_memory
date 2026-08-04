import 'package:flutter_agent_memory/src/agents/prompts/prompt_loader.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    PromptLoader.setLoader(null);
  });

  const xmlWithConditional = r'''
<prompt>
<extra_instructions if="extraInstructions">${extraInstructions}</extra_instructions>
</prompt>
''';

  test('loads a real prompt and substitutes variables', () async {
    final prompt = await PromptLoader.load('kb_analysis.xml', {
      'inputText': 'Hello world',
    });

    expect(prompt, contains('Hello world'));
  });

  test('includes conditional block when variable is non-empty', () async {
    PromptLoader.setLoader((_) async => xmlWithConditional);
    final prompt = await PromptLoader.load('test_include.xml', {
      'extraInstructions': 'Be concise.',
    });

    expect(prompt, contains('Be concise.'));
  });

  test('loadSync throws when no cached prompt exists', () {
    expect(
      () => PromptLoader.loadSync('not-cached.xml', {}),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('loadSync uses cached prompt without hitting loader', () async {
    await PromptLoader.load('kb_analysis.xml', {'inputText': 'x'});
    final prompt = PromptLoader.loadSync('kb_analysis.xml', {'inputText': 'y'});
    expect(prompt, contains('y'));
  });

  test('removes conditional block when variable is empty', () async {
    PromptLoader.setLoader((_) async => xmlWithConditional);
    final prompt = await PromptLoader.load('test_exclude.xml', {
      'extraInstructions': '',
    });

    expect(prompt, isNot(contains('extra_instructions')));
    expect(prompt, isNot(contains('Be concise.')));
  });
}
