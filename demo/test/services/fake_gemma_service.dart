import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:demo/services/gemma_model_presets.dart';
import 'package:demo/services/gemma_service.dart';

class FakeGemmaService implements GemmaService {
  final installed = <String>{};
  var initializeCalled = false;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<bool> isModelInstalled(GemmaModelPreset preset) async {
    return installed.contains(preset.id);
  }

  @override
  Stream<double> installModel(GemmaModelPreset preset, {String? hfToken}) async* {
    installed.add(preset.id);
    yield 50;
    yield 100;
  }

  @override
  Future<InferenceModel> loadModel(GemmaModelPreset preset) async {
    if (!installed.contains(preset.id)) {
      throw StateError('Model ${preset.id} not installed');
    }
    throw UnimplementedError('Inference is not implemented in fake service');
  }
}
