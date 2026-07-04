// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:integration_test/integration_test.dart';

import 'package:demo/services/gemma_model_presets.dart';
import 'package:demo/services/gemma_service.dart';

/// Probes the real context-window limits of on-device Gemma/LiteRT-LM models
/// on macOS desktop by sending prompts of increasing length.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('macOS Gemma context probing', () {
    // Public, desktop-compatible .litertlm presets we want to characterize.
    final presets = <GemmaModelPreset>[
      gemmaModelPresets.firstWhere((p) => p.id == 'gemma4-e2b-litertlm'),
      gemmaModelPresets.firstWhere((p) => p.id == 'qwen3-0.6b'),
      gemmaModelPresets.firstWhere((p) => p.id == 'phi4-mini'),
      gemmaModelPresets.firstWhere((p) => p.id == 'functiongemma-270m'),
    ];

    for (final preset in presets) {
      testWidgets('${preset.id} context probe', (tester) async {
        // Initialize the plugin directly; we don't need the full app UI for
        // a programmatic probe, and launching the app keeps a SemanticsHandle
        // alive that makes the integration test fail at teardown.
        final service = FlutterGemmaService();
        await service.initialize();

        if (!await service.isModelInstalled(preset)) {
          print('[PROBE] Downloading ${preset.displayName} (${preset.size})...');
          await for (final progress in service.installModel(preset)) {
            print('[PROBE] download ${preset.id}: $progress%');
          }
        }

        final results = <String>[];

        // Probe input lengths from tiny up to the preset's claimed maxTokens.
        // We keep maxOutputTokens tiny so the budget is available for input.
        final probeTargets = <int>[
          512,
          1024,
          2048,
          4096,
          8192,
          16384,
          32768,
          65536,
          100000,
        ].where((t) => t <= preset.maxTokens).toList();

        for (final targetTokens in probeTargets) {
          final result = await _probePreset(
            service: service,
            preset: preset,
            targetInputTokens: targetTokens,
          );
          results.add('${preset.id} target=${targetTokens}t -> $result');
          print('[PROBE] ${results.last}');
        }

        // Run one realistic analysis-like task on a ~2k-token transcript chunk.
        final analysisResult = await _probeAnalysis(
          service: service,
          preset: preset,
        );
        results.add('${preset.id} analysis-task -> $analysisResult');
        print('[PROBE] ${results.last}');

        // Print a machine-readable summary the CI/user can read from logs.
        print('[PROBE] SUMMARY ${preset.id}: ${results.join(" | ")}');
      });
    }
  });
}

/// Returns a short text that approximates [targetTokens] tokens.
String _generateLongText(int targetTokens) {
  // Very rough heuristic: ~4 chars per token for English-ish prose.
  final targetChars = targetTokens * 4;
  final buffer = StringBuffer();
  const sentence =
      'The quick brown fox jumps over the lazy dog while the user explains '
      'their problem in a technical conversation about software engineering. ';
  while (buffer.length < targetChars) {
    buffer.write(sentence);
  }
  return buffer.toString().substring(0, math.min(buffer.length, targetChars));
}

Future<String> _probePreset({
  required GemmaService service,
  required GemmaModelPreset preset,
  required int targetInputTokens,
}) async {
  final text = _generateLongText(targetInputTokens);
  final prompt =
      'The following text is exactly $targetInputTokens tokens long. '
      'Reply with ONLY the single word that appears at the very end of it.\n\n'
      '$text\n\nEND. Now reply with the last word.';

  try {
    final model = await service.loadModel(preset);
    final session = await model.createSession(
      temperature: preset.temperature,
      topK: preset.topK,
      topP: preset.topP,
      maxOutputTokens: 32,
    );
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      final buffer = StringBuffer();
      await for (final token in session.getResponseAsync()) {
        buffer.write(token);
      }
      final response = buffer.toString().trim();
      final ok = response.isNotEmpty &&
          (response.toLowerCase().contains('engineering') ||
              response.toLowerCase().contains('dog'));
      return 'OK len=${response.length} approx_input=${prompt.length ~/ 4}t coherent=$ok';
    } finally {
      await session.close();
    }
  } catch (e) {
    return 'FAIL: $e';
  }
}

Future<String> _probeAnalysis({
  required GemmaService service,
  required GemmaModelPreset preset,
}) async {
  const transcript = '''
[00:00:11] Uladzimir Klyshevich: more difficult and different approach when you have multi repositories and agents in separate repository. Now we will try to simplify a bit.
[00:00:24] Stefan Murphy: There.
[00:00:27] Uladzimir Klyshevich: and we will try to replicate exactly the same processes which we have in my tube and uses for TM.
[00:04:49] Aliaksei Yermachonak: Why do we need VPN now?
[00:04:52] Uladzimir Klyshevich: Because Copilot does not work without VPN from Belarus.
[00:05:01] Sergey Makarevich: And a choice of superset as IDE. Could you remind?
[00:05:07] Uladzimir Klyshevich: Actually, I don't need IDE because I don't review the code. So sometimes, yes, I do, but I don't need IDE at all, to be honest.
''';
  final prompt =
      'Extract all questions, answers and notes from the transcript below. '
      'Return ONLY a JSON object with keys questions, answers, notes.\n\n$transcript';

  try {
    final model = await service.loadModel(preset);
    final session = await model.createSession(
      temperature: preset.temperature,
      topK: preset.topK,
      topP: preset.topP,
      maxOutputTokens: preset.maxOutputTokens,
    );
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      final buffer = StringBuffer();
      await for (final token in session.getResponseAsync()) {
        buffer.write(token);
      }
      final response = buffer.toString().trim();
      final hasJson = response.contains('{') && response.contains('}');
      return 'OK len=${response.length} has_json=$hasJson';
    } finally {
      await session.close();
    }
  } catch (e) {
    return 'FAIL: $e';
  }
}
