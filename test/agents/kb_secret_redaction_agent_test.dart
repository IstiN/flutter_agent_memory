import 'package:flutter_agent_memory/src/agents/kb_secret_redaction_agent.dart';
import 'package:test/test.dart';

void main() {
  test('redacts OpenAI API key', () {
    final text = 'My key is sk-abc12345678901234567890 and some text.';
    expect(
      KBSecretRedactionAgent.redact(text),
      'My key is [REDACTED_SECRET] and some text.',
    );
  });

  test('redacts password assignment', () {
    final text = 'password = "superSecret123"';
    expect(
      KBSecretRedactionAgent.redact(text),
      '[REDACTED_SECRET]',
    );
  });

  test('redacts private key block', () {
    final text = '''
-----BEGIN OPENSSH PRIVATE KEY-----
abc123
-----END OPENSSH PRIVATE KEY-----''';
    expect(KBSecretRedactionAgent.redact(text), '[REDACTED_SECRET]');
  });

  test('leaves benign text unchanged', () {
    const text = 'Dart is a programming language.';
    expect(KBSecretRedactionAgent.redact(text), text);
  });
}
