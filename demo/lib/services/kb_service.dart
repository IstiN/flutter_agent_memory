import 'package:flutter/foundation.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import 'provider_service.dart';
import 'settings_service.dart';

/// Holds the active memory store, search engine, and graph builder.
///
/// Recreates the store/engine when the provider settings change while keeping
/// the same storage backend.
class KbService extends ChangeNotifier {
  final SettingsService settings;
  final ProviderService providerService;
  final KbStorage _storage;

  late KBMemoryStore store;
  late KBSearchEngine engine;
  late KBGraphBuilder graphBuilder;

  KbStorage get storage => _storage;

  KbService(
    this.settings,
    this.providerService, {
    KbStorage? storage,
  }) : _storage = storage ?? WebKbStorage() {
    _rebuild();
  }

  void rebuild() {
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    final provider = providerService.provider;
    store = KBMemoryStore(_storage, provider: provider, source: 'demo');
    engine = KBSearchEngine(_storage, provider: provider);
    graphBuilder = KBGraphBuilder(_storage);
  }

  Future<void> updateSettings({
    required String provider,
    required String apiKey,
    required String model,
    required String baseUrl,
  }) async {
    await settings.save(
      provider: provider,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl,
    );
    _rebuild();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _storage.initialize(clean: true);
    notifyListeners();
  }
}
