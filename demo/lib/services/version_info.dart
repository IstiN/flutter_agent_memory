import 'package:package_info_plus/package_info_plus.dart';

/// Runtime version info for the web demo.
///
/// Values are loaded asynchronously from package_info_plus (app version) and
/// from compile-time constants for the key libraries. [format()] returns a
/// single-line string suitable for console logs and UI footers.
class DemoVersionInfo {
  final String appVersion;
  final String appBuildNumber;
  final String flutterGemmaVersion;
  final String flutterGemmaLitertlmVersion;
  final String flutterGemmaMediapipeVersion;
  final String flutterAgentMemoryVersion;

  final String webLlmVersion;

  const DemoVersionInfo({
    required this.appVersion,
    required this.appBuildNumber,
    required this.flutterGemmaVersion,
    required this.flutterGemmaLitertlmVersion,
    required this.flutterGemmaMediapipeVersion,
    required this.flutterAgentMemoryVersion,
    required this.webLlmVersion,
  });

  static const _flutterGemmaVersion = '1.2.0';
  static const _flutterGemmaLitertlmVersion = '1.0.2';
  static const _flutterGemmaMediapipeVersion = '1.0.3';
  static const _flutterAgentMemoryVersion = '0.0.2';
  static const _webLlmVersion = '0.2.81';

  static Future<DemoVersionInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return DemoVersionInfo(
      appVersion: info.version,
      appBuildNumber: info.buildNumber,
      flutterGemmaVersion: _flutterGemmaVersion,
      flutterGemmaLitertlmVersion: _flutterGemmaLitertlmVersion,
      flutterGemmaMediapipeVersion: _flutterGemmaMediapipeVersion,
      flutterAgentMemoryVersion: _flutterAgentMemoryVersion,
      webLlmVersion: _webLlmVersion,
    );
  }

  /// Short single-line summary for console logs.
  String get summary {
    return 'demo $appVersion+$appBuildNumber | '
        'fam $_flutterAgentMemoryVersion | '
        'webllm $_webLlmVersion | '
        'gemma $_flutterGemmaVersion | '
        'litertlm $_flutterGemmaLitertlmVersion | '
        'mediapipe $_flutterGemmaMediapipeVersion';
  }

  /// Multi-line block suitable for a settings footer or about dialog.
  String format() {
    return 'Flutter Agent Memory Demo v$appVersion+$appBuildNumber\n'
        'flutter_agent_memory: $_flutterAgentMemoryVersion\n'
        'webllm: $_webLlmVersion\n'
        'flutter_gemma: $_flutterGemmaVersion\n'
        'flutter_gemma_litertlm: $_flutterGemmaLitertlmVersion\n'
        'flutter_gemma_mediapipe: $_flutterGemmaMediapipeVersion';
  }
}
