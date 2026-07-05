// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo/services/gemma_model_presets.dart';
import 'package:demo/services/gemma_service.dart';
import 'package:demo/services/prompt_asset_loader.dart';
import 'package:demo/services/provider_service.dart';
import 'package:demo/services/raw_text_processor_service.dart';
import 'package:demo/services/settings_service.dart';
import 'package:demo/webllm/webllm_service.dart';

class _TestCase {
  final String name;
  final String path;
  final int charCount;
  final int approxTokens;

  _TestCase({
    required this.name,
    required this.path,
    required this.charCount,
    required this.approxTokens,
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding.ensureInitialized();
  initializePromptAssetLoader();

  final transcriptDir = '/Users/Uladzimir_Klyshevich/git/flutter_agent_memory/demo/test_inputs';
  final files = [
    ('session_4_transcript.vtt', 500),
    ('df_session_1_transcript.vtt', 14000),
  ];

  final cases = <_TestCase>[];
  for (final (rel, approx) in files) {
    final src = File('$transcriptDir/$rel');
    if (!src.existsSync()) continue;
    final text = src.readAsStringSync();
    cases.add(_TestCase(
      name: rel,
      path: src.path,
      charCount: text.length,
      approxTokens: approx,
    ));
  }

  group('Gemma4 RawTextProcessor sweep', () {
    for (final c in cases) {
      testWidgets(
        'file=${c.name} chars=${c.charCount}',
        (tester) async {
          final prefs = await SharedPreferences.getInstance();
          // Do NOT clear all prefs: flutter_gemma stores model-repository
          // metadata in SharedPreferences, and clearing it makes the plugin
          // think an already-downloaded model is missing, causing a redundant
          // 2.4 GB re-download between test cases.
          await prefs.setString('provider', 'gemma');
          await prefs.setString('model', 'gemma4-e2b-litertlm');

          final settings = SettingsService(prefs);
          final gemmaService = FlutterGemmaService();
          final providerService = ProviderService(
            settings,
            gemmaService: gemmaService,
            webLlmService: WebLlmService(),
          );

          final preset = findGemmaPreset('gemma4-e2b-litertlm')!;
          if (!await gemmaService.isModelInstalled(preset)) {
            print('[CtxSweep] downloading ${preset.displayName}...');
            await for (final p in gemmaService.installModel(preset)) {
              print('[CtxSweep] download: $p%');
            }
          }

          final processor = RawTextProcessorService(providerService);
          final stopwatch = Stopwatch()..start();
          Object? error;
          Map<String, dynamic>? result;
          try {
            result = await processor.process(File(c.path).readAsStringSync());
          } catch (e) {
            error = e;
          }
          stopwatch.stop();

          final questions = (result?['questions'] as List? ?? []).length;
          final answers = (result?['answers'] as List? ?? []).length;
          final notes = (result?['notes'] as List? ?? []).length;

          print('[CtxSweep] file=${c.name} '
              'chars=${c.charCount} approx=${c.approxTokens} '
              'time=${stopwatch.elapsed.inSeconds}s '
              'error=$error '
              'q=$questions a=$answers n=$notes');

          expect(error, isNull, reason: '${c.name} should not throw');
          expect(result, isNotNull, reason: '${c.name} should return a result');
        },
        timeout: const Timeout(Duration(minutes: 30)),
      );
    }
  });
}
