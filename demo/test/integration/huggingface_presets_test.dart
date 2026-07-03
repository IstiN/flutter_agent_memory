import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:demo/services/gemma_model_presets.dart';

/// Real HuggingFace smoke test.
///
/// Requires a HuggingFace read token in the HUGGINGFACE_TOKEN environment
/// variable. It verifies that every model preset URL is reachable and returns
/// a model file. It does NOT download or run inference.
///
/// Run with:
///   HUGGINGFACE_TOKEN=hf_xxx flutter test demo/test/integration/huggingface_presets_test.dart
void main() {
  group('HuggingFace preset URLs', () {
    final token = Platform.environment['HUGGINGFACE_TOKEN'];

    setUpAll(() {
      if (token == null || token.isEmpty) {
        markTestSkipped('HUGGINGFACE_TOKEN is not set');
      }
    });

    for (final preset in gemmaModelPresets) {
      test('${preset.id} is reachable', () async {
        final client = HttpClient();
        try {
          // HEAD from HF often omits Content-Type, so we request a single byte
          // with Range to get real headers without downloading the model.
          final request = await client.getUrl(Uri.parse(preset.url));
          request.headers.add('Authorization', 'Bearer $token');
          request.headers.add('Range', 'bytes=0-0');
          final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
          await response.drain<void>();

          // Gated models that the token cannot access are reported as skipped
          // rather than failures so the suite stays useful for a normal token.
          if (preset.needsAuth && response.statusCode == 403) {
            markTestSkipped(
              '${preset.id}: token cannot access gated repo ${preset.url}',
            );
            return;
          }

          expect(
            response.statusCode,
            anyOf(equals(200), equals(206)),
            reason:
                '${preset.id}: ${preset.url} returned ${response.statusCode}',
          );

          final contentLength = response.headers.contentLength;
          expect(
            contentLength,
            greaterThan(0),
            reason: '${preset.id}: missing Content-Length',
          );
        } finally {
          client.close();
        }
      });
    }
  });
}
