import 'dart:io';

/// Loads Ollama credentials from `.env` in the project root.
///
/// Falls back to environment variables and, finally, to the original yoloit
/// clip file for backwards compatibility.
class OllamaConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool configured;

  OllamaConfig._({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.configured,
  });

  static const String _defaultFilePath =
      '/var/folders/rb/mdj9k7w532d7s78dzhr0b1dm0000gn/T/yoloit_clip/clip_1782685098728.txt';

  factory OllamaConfig.load() {
    final env = Platform.environment;
    final values = <String, String>{};

    void parseLines(List<String> lines) {
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final idx = trimmed.indexOf('=');
        if (idx == -1) continue;
        values[trimmed.substring(0, idx).trim()] = trimmed
            .substring(idx + 1)
            .trim();
      }
    }

    // 1. Project-root `.env`
    final dotEnv = File('.env');
    if (dotEnv.existsSync()) {
      parseLines(dotEnv.readAsLinesSync());
    }

    // 2. Legacy clip file
    final clipFile = File(env['OLLAMA_CONFIG_FILE'] ?? _defaultFilePath);
    if (values.isEmpty && clipFile.existsSync()) {
      parseLines(clipFile.readAsLinesSync());
    }

    String? base = values['OLLAMA_BASE_URL'] ?? env['OLLAMA_BASE_URL'];
    final key = values['OLLAMA_API_KEY'] ?? env['OLLAMA_API_KEY'];
    final model = values['OLLAMA_MODEL'] ?? env['OLLAMA_MODEL'];

    if (base != null && !base.endsWith('/v1/chat/completions')) {
      base = '${base.replaceAll(RegExp(r'/+$'), '')}/v1/chat/completions';
    }

    final configured =
        base != null &&
        key != null &&
        model != null &&
        base.isNotEmpty &&
        key.isNotEmpty &&
        model.isNotEmpty;

    return OllamaConfig._(
      baseUrl: base ?? '',
      apiKey: key ?? '',
      model: model ?? '',
      configured: configured,
    );
  }
}
