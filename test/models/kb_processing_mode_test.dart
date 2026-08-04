import 'package:flutter_agent_memory/src/models/kb_processing_mode.dart';
import 'package:test/test.dart';

void main() {
  test('parses full mode', () {
    expect(KBProcessingModeParsing.fromString('full'), KBProcessingMode.full);
  });

  test('parses process mode variants', () {
    expect(KBProcessingModeParsing.fromString('process_only'), KBProcessingMode.processOnly);
    expect(KBProcessingModeParsing.fromString('process-only'), KBProcessingMode.processOnly);
    expect(KBProcessingModeParsing.fromString('process'), KBProcessingMode.processOnly);
  });

  test('parses aggregate mode variants', () {
    expect(KBProcessingModeParsing.fromString('aggregate_only'), KBProcessingMode.aggregateOnly);
    expect(KBProcessingModeParsing.fromString('aggregate-only'), KBProcessingMode.aggregateOnly);
    expect(KBProcessingModeParsing.fromString('aggregate'), KBProcessingMode.aggregateOnly);
  });

  test('defaults to full for unknown values', () {
    expect(KBProcessingModeParsing.fromString('unknown'), KBProcessingMode.full);
  });
}
