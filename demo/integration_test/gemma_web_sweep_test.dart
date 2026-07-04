import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo/llm/gemma_llm_provider.dart';
import 'package:demo/services/gemma_model_presets.dart';
import 'package:demo/services/gemma_service.dart';
import 'package:demo/services/prompt_asset_loader.dart';
import 'package:demo/services/provider_service.dart';
import 'package:demo/services/raw_text_processor_service.dart';
import 'package:demo/services/settings_service.dart';

/// Verifies the Gemma 4 E2B web LiteRT-LM model can load and process a small
/// transcript in Chrome. Uses an embedded transcript so it works without
/// dart:io file access on the web.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding.ensureInitialized();
  initializePromptAssetLoader();

  const transcript = '''
[2024-11-15T09:00:00Z] Alice: How do I manage state in Flutter?
[2024-11-15T09:01:00Z] Bob: Use Riverpod or Bloc.
[2024-11-15T09:02:00Z] Alice: How do I write unit tests in Dart?
[2024-11-15T09:03:00Z] Bob: Use the test package.
''';

  group('Gemma4 web LiteRT-LM raw text processor', () {
    testWidgets(
      'processes a short transcript',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('provider', 'gemma');
        await prefs.setString('model', 'gemma4-e2b-litertlm');

        final settings = SettingsService(prefs);
        final gemmaService = FlutterGemmaService();
        final providerService = ProviderService(
          settings,
          gemmaService: gemmaService,
        );

        final preset = findGemmaPreset('gemma4-e2b-litertlm')!;
        if (!await gemmaService.isModelInstalled(preset)) {
          print('[WebSweep] downloading ${preset.displayName} (${preset.size})...');
          await for (final p in gemmaService.installModel(preset)) {
            print('[WebSweep] download: $p%');
          }
        }

        final processor = RawTextProcessorService(providerService);
        final stopwatch = Stopwatch()..start();
        Object? error;
        Map<String, dynamic>? result;
        try {
          result = await processor.process(transcript);
        } catch (e) {
          error = e;
        }
        stopwatch.stop();

        final questions = (result?['questions'] as List? ?? []).length;
        final answers = (result?['answers'] as List? ?? []).length;
        final notes = (result?['notes'] as List? ?? []).length;

        print('[WebSweep] time=${stopwatch.elapsed.inSeconds}s '
            'error=$error q=$questions a=$answers n=$notes');

        expect(error, isNull, reason: 'web processing should not throw');
        expect(result, isNotNull, reason: 'web processing should return a result');
      },
      timeout: const Timeout(Duration(minutes: 30)),
    );
  });
}
