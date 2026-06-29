import 'dart:convert';
import 'dart:io';

import '../models/source_config.dart';
import '../utils/date_utils.dart';

/// Loads and persists per-source sync metadata.
class SourceConfigManager {
  static const String _configFileName = 'inbox/source_config.json';

  SourceConfig loadConfig(Directory outputDir) {
    final file = File('${outputDir.path}/$_configFileName');
    if (!file.existsSync()) return SourceConfig();
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return SourceConfig.fromJson(json);
    } catch (_) {
      return SourceConfig();
    }
  }

  void saveConfig(SourceConfig config, Directory outputDir) {
    final file = File('${outputDir.path}/$_configFileName');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(config.toJson()));
  }

  void updateLastSyncDate(String sourceName, Directory outputDir) {
    final config = loadConfig(outputDir);
    final now = currentUtcTimestamp();
    config.sources[sourceName] = SourceInfo(lastSyncDate: now, updatedAt: now);
    saveConfig(config, outputDir);
  }
}
