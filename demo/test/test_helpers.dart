import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo/services/kb_service.dart';
import 'package:demo/services/provider_service.dart';
import 'package:demo/services/settings_service.dart';

import 'services/fake_gemma_service.dart';

Future<SettingsService> createTestSettings([
  Map<String, Object>? values,
]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return SettingsService.load();
}

Future<KbService> createTestKbService({
  SettingsService? settings,
  KbStorage? storage,
}) async {
  final s = settings ?? await createTestSettings();
  return KbService(
    s,
    ProviderService(s, gemmaService: FakeGemmaService()),
    storage: storage ?? InMemoryKbStorage(),
  );
}
