/// Per-source sync metadata stored in `inbox/source_config.json`.
class SourceConfig {
  final Map<String, SourceInfo> sources;

  SourceConfig({Map<String, SourceInfo>? sources})
      : sources = sources ?? <String, SourceInfo>{};

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    final sources = <String, SourceInfo>{};
    final raw = json['sources'] as Map<String, dynamic>?;
    if (raw != null) {
      for (final entry in raw.entries) {
        sources[entry.key] = SourceInfo.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    return SourceConfig(sources: sources);
  }

  Map<String, dynamic> toJson() => {
        'sources': sources.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class SourceInfo {
  String lastSyncDate;
  String updatedAt;

  SourceInfo({required this.lastSyncDate, required this.updatedAt});

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
        lastSyncDate: json['lastSyncDate'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'lastSyncDate': lastSyncDate,
        'updatedAt': updatedAt,
      };
}
