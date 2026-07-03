import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'gemma_model_presets.dart';

/// Abstract interface for Flutter Gemma model management.
///
/// Allows tests to inject a fake service without pulling in native/web engines.
abstract class GemmaService {
  Future<void> initialize();

  Future<bool> isModelInstalled(GemmaModelPreset preset);

  /// Downloads and installs a model. Emits progress 0–100.
  Stream<double> installModel(GemmaModelPreset preset, {String? hfToken});

  /// Loads the currently-active inference model.
  ///
  /// Throws if the model is not installed.
  Future<InferenceModel> loadModel(GemmaModelPreset preset);
}

/// Concrete Flutter Gemma service backed by the plugin.
class FlutterGemmaService implements GemmaService {
  GemmaModelPreset? _loadedPreset;
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() async {
    if (_initFuture != null) return _initFuture!;
    dev.log('[GemmaService] initializing FlutterGemma...');
    _initFuture = FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine(), MediaPipeEngine()],
    );
    await _initFuture!;
    dev.log('[GemmaService] FlutterGemma initialized');
    return _initFuture!;
  }

  @override
  Future<void> initialize() => _ensureInitialized();

  @override
  Future<bool> isModelInstalled(GemmaModelPreset preset) async {
    await _ensureInitialized();
    final installed = await FlutterGemma.isModelInstalled(preset.filename);
    dev.log('[GemmaService] isModelInstalled(${preset.id}) = $installed');
    return installed;
  }

  @override
  Stream<double> installModel(GemmaModelPreset preset, {String? hfToken}) {
    final controller = StreamController<double>();
    _ensureInitialized().then((_) {
      FlutterGemma.installModel(
        modelType: preset.modelType,
        fileType: preset.fileType,
      )
          .fromNetwork(preset.url, token: hfToken)
          .withProgress((progress) {
            if (!controller.isClosed) controller.add(progress.toDouble());
          })
          .install()
          .then((_) {
            if (!controller.isClosed) {
              controller.add(100);
              controller.close();
            }
          })
          .catchError((Object e, StackTrace s) {
            if (!controller.isClosed) {
              controller.addError(e, s);
              controller.close();
            }
          });
    }).catchError((Object e, StackTrace s) {
      if (!controller.isClosed) {
        controller.addError(e, s);
        controller.close();
      }
    });
    return controller.stream;
  }

  @override
  Future<InferenceModel> loadModel(GemmaModelPreset preset) async {
    dev.log('[GemmaService] loadModel(${preset.id}) start');
    final installed = await isModelInstalled(preset);
    if (!installed) {
      throw StateError(
        'Model "${preset.displayName}" is not installed. Install it first.',
      );
    }
    if (_loadedPreset?.id == preset.id) {
      final cached = FlutterGemmaPlugin.instance.initializedModel;
      if (cached != null) {
        dev.log('[GemmaService] loadModel(${preset.id}) using cached model');
        return cached;
      }
    }
    dev.log('[GemmaService] loadModel(${preset.id}) calling getActiveModel...');
    final model = await FlutterGemma.getActiveModel(
      maxTokens: preset.maxTokens,
      preferredBackend: preset.preferredBackend,
    );
    _loadedPreset = preset;
    dev.log('[GemmaService] loadModel(${preset.id}) done');
    return model;
  }
}
