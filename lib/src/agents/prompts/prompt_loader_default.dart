import 'dart:io';
import 'dart:isolate';

/// Default VM prompt loader that resolves files via `Isolate.resolvePackageUri`.
Future<String> loadPromptFile(String name) async {
  final packageUri = Uri.parse(
    'package:flutter_agent_memory/src/agents/prompts/$name',
  );
  final resolved = await Isolate.resolvePackageUri(packageUri);
  if (resolved == null) {
    throw StateError('Could not resolve prompt asset: $packageUri');
  }
  final file = File.fromUri(resolved);
  if (!file.existsSync()) {
    throw StateError('Prompt file not found: ${file.path}');
  }
  return file.readAsString();
}
