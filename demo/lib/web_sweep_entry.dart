import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/gemma_model_presets.dart';
import 'services/gemma_service.dart';
import 'services/prompt_asset_loader.dart';
import 'services/provider_service.dart';
import 'services/raw_text_processor_service.dart';
import 'services/settings_service.dart';

const _transcript = '''
[2024-11-15T09:00:00Z] Alice: How do I manage state in Flutter?
[2024-11-15T09:01:00Z] Bob: Use Riverpod or Bloc.
[2024-11-15T09:02:00Z] Alice: How do I write unit tests in Dart?
[2024-11-15T09:03:00Z] Bob: Use the test package.
''';

void _emit(String label, String message) {
  final line = '[WebSweep] $label: $message';
  // ignore: avoid_print
  print(line);
  try {
    html.window.console.log(line);
  } catch (_) {}
}

void _setResult(Map<String, String> data) {
  try {
    html.document.title = 'WebSweep ${data['error']?.isNotEmpty == true ? 'ERROR' : 'OK'}';
    final body = html.document.body;
    if (body != null) {
      final pre = html.document.createElement('pre');
      pre.text = data.entries.map((e) => '${e.key}=${e.value}').join('\n');
      body.append(pre);
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializePromptAssetLoader();

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SelectableText(
            'Gemma web sweep running...',
            key: const ValueKey('status'),
          ),
        ),
      ),
    ),
  );

  _emit('INIT', 'starting web sweep');

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('provider', 'gemma');
  await prefs.setString('model', 'gemma4-e2b-litertlm');

  final settings = SettingsService(prefs);
  final gemmaService = FlutterGemmaService();
  final providerService = ProviderService(settings, gemmaService: gemmaService);
  final processor = RawTextProcessorService(providerService);

  _emit('MODEL', 'checking/installing gemma4-e2b-litertlm');

  final preset = findGemmaPreset('gemma4-e2b-litertlm')!;
  if (!await gemmaService.isModelInstalled(preset)) {
    _emit('MODEL', 'downloading ${preset.displayName} (${preset.size})...');
    await for (final progress in gemmaService.installModel(preset)) {
      _emit('MODEL', 'download progress ${progress.toStringAsFixed(1)}%');
    }
  }

  _emit('MODEL', 'model ready, processing transcript');

  final stopwatch = Stopwatch()..start();
  Object? error;
  Map<String, dynamic>? result;
  try {
    result = await processor.process(_transcript);
  } catch (e, st) {
    error = e;
    _emit('ERROR', '$e\n$st');
  }
  stopwatch.stop();

  final questions = (result?['questions'] as List? ?? []).length;
  final answers = (result?['answers'] as List? ?? []).length;
  final notes = (result?['notes'] as List? ?? []).length;

  _emit(
    'DONE',
    'time=${stopwatch.elapsed.inSeconds}s error=$error q=$questions a=$answers n=$notes',
  );

  // Also write a machine-readable result into the DOM for Playwright/tests.
  _setResult({
    'done': 'true',
    'error': error?.toString() ?? '',
    'questions': questions.toString(),
    'answers': answers.toString(),
    'notes': notes.toString(),
    'timeSeconds': stopwatch.elapsed.inSeconds.toString(),
  });
}
