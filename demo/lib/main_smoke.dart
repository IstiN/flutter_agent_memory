import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'services/gemma_model_presets.dart';
import 'services/gemma_service.dart';

/// One-shot smoke entry point for real on-device inference verification.
///
/// Uses the FunctionGemma 270M MediaPipe .task model because it is reachable
/// with the provided token and works with MediaPipe in headless Chrome.
///
/// Build and run with:
///   flutter build web -t lib/main_smoke.dart \
///     --dart-define=HUGGINGFACE_TOKEN=hf_xxx \
///     --dart-define=GEMMA_BACKEND=cpu
///
/// The result is written to a hidden DOM element (#smoke-result) and mirrored
/// to the browser console, so a headless browser can scrape it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _ensureSmokeElements();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text(
            'Gemma smoke test in progress...\nSee console / #smoke-result',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );

  const token = String.fromEnvironment('HUGGINGFACE_TOKEN');
  const backendName = String.fromEnvironment('GEMMA_BACKEND', defaultValue: 'cpu');
  final backend = backendName == 'cpu' ? PreferredBackend.cpu : PreferredBackend.gpu;
  // Use a MediaPipe .task model. LiteRT-LM prefill/decode models do not
  // support the streaming path used by getResponse() in headless Chrome.
  final preset = findGemmaPreset('functiongemma-270m-task');

  if (preset == null) {
    _fail('Preset functiongemma-270m-task not found');
    return;
  }
  if (token.isEmpty) {
    _fail('HUGGINGFACE_TOKEN is empty');
    return;
  }

  _log('Using backend: $backendName');

  // MediaPipe .task models work in headless Chrome with CPU/WASM; LiteRT-LM
  // models require a real GPU/WebGPU adapter.
  final service = FlutterGemmaService(
    inferenceEngines: const [MediaPipeEngine()],
  );
  try {
    _log('Initializing FlutterGemma...');
    await service.initialize();
    _log('FlutterGemma initialized');

    if (!await service.isModelInstalled(preset)) {
      _log('Downloading ${preset.id} (${preset.size})...');
      await for (final progress in service.installModel(preset, hfToken: token)) {
        _log('Download progress: ${progress.toStringAsFixed(1)}%');
      }
    } else {
      _log('Model ${preset.id} already installed');
    }

    _log('Loading model with $backendName backend...');
    final model = await service.loadModel(preset, backend: backend);
    _log('Model loaded');

    _log('Creating session...');
    final session = await model.createSession(
      temperature: preset.temperature,
      topK: preset.topK,
      topP: preset.topP,
      maxOutputTokens: preset.maxTokens,
    );

    try {
      const prompt = 'What is 2+2? Answer with a single number.';
      _log('Sending prompt: "$prompt"');
      await session.addQueryChunk(
        Message.text(text: prompt, isUser: true),
      );
      _log('Waiting for response...');
      final response = await session.getResponse();
      _log('Response: $response');

      final passed = response.contains('4');
      _finish(passed, response);
    } finally {
      await session.close();
    }
  } catch (e, s) {
    _fail('Exception: $e\n$s');
  }
}

void _ensureSmokeElements() {
  void ensure(String id, {bool hidden = false}) {
    if (html.document.getElementById(id) != null) return;
    final el = html.DivElement()..id = id;
    if (hidden) el.style.display = 'none';
    html.document.body?.append(el);
  }

  ensure('smoke-result', hidden: true);
  ensure('smoke-logs');
}

void _log(String message) {
  final line = '[GemmaSmoke] $message';
  if (kDebugMode) debugPrint(line);
  html.window.console.log(line);

  final logs = html.document.getElementById('smoke-logs');
  if (logs != null) {
    logs.text = logs.text!.isEmpty ? line : '${logs.text}\n$line';
  }
}

void _setResult(bool passed, String detail) {
  final result = html.document.getElementById('smoke-result');
  if (result != null) {
    result.setAttribute('data-passed', passed.toString());
    result.text = detail;
  }
}

void _finish(bool passed, String detail) {
  _setResult(passed, detail);
  _log(passed ? 'SMOKE PASSED' : 'SMOKE FAILED');

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: passed ? Colors.green[900] : Colors.red[900],
        body: Center(
          child: Text(
            passed ? 'SMOKE PASSED' : 'SMOKE FAILED',
            style: const TextStyle(fontSize: 32, color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

void _fail(String detail) {
  _log('FAIL: $detail');
  _finish(false, detail);
}
