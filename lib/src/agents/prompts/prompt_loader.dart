import 'dart:io';
import 'dart:isolate';

import 'package:xml/xml.dart';

/// Loads prompt templates stored as XML files under
/// `lib/src/agents/prompts/`.
///
/// Each XML file may contain placeholders in the form `${variableName}` and
/// conditional blocks:
///
/// ```xml
/// <extra_instructions if="extraInstructions">
///   ${extraInstructions}
/// </extra_instructions>
/// ```
///
/// The block is included only when the `extraInstructions` variable is present
/// and non-empty.
class PromptLoader {
  static final Map<String, String> _cache = {};

  /// Loads and renders the prompt named [name] (e.g. `kb_analysis.xml`).
  ///
  /// [variables] are substituted for `${key}` placeholders. Missing variables
  /// are replaced with an empty string.
  static Future<String> load(String name, Map<String, String> variables) async {
    final cached = _cache[name];
    if (cached != null) {
      return _render(cached, variables);
    }

    final file = await _resolvePromptFile(name);
    final raw = await file.readAsString();
    _cache[name] = raw;
    return _render(raw, variables);
  }

  /// Synchronous version. Use when calling from already-async code that prefers
  /// to avoid an extra await.
  static String loadSync(String name, Map<String, String> variables) {
    final cached = _cache[name];
    if (cached != null) {
      return _render(cached, variables);
    }

    final file = _resolvePromptFileSync(name);
    final raw = file.readAsStringSync();
    _cache[name] = raw;
    return _render(raw, variables);
  }

  static Future<File> _resolvePromptFile(String name) async {
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
    return file;
  }

  static File _resolvePromptFileSync(String name) {
    final packageUri = Uri.parse(
      'package:flutter_agent_memory/src/agents/prompts/$name',
    );
    final resolved = Isolate.resolvePackageUriSync(packageUri);
    if (resolved == null) {
      throw StateError('Could not resolve prompt asset: $packageUri');
    }
    final file = File.fromUri(resolved);
    if (!file.existsSync()) {
      throw StateError('Prompt file not found: ${file.path}');
    }
    return file;
  }

  static String _render(String raw, Map<String, String> variables) {
    final document = XmlDocument.parse(raw);
    final root = document.rootElement;

    // Process conditional blocks first.
    _processConditionals(root, variables);

    // Replace placeholders.
    final text = _innerText(root);
    return _replacePlaceholders(text, variables).trim();
  }

  static void _processConditionals(XmlNode node, Map<String, String> variables) {
    for (final element in List<XmlElement>.from(node.descendantElements)) {
      final attr = element.attributes
          .cast<XmlAttribute?>()
          .firstWhere(
            (a) => a != null && a.name.local == 'if',
            orElse: () => null,
          );
      if (attr == null) continue;

      final key = attr.value;
      final value = variables[key] ?? '';
      if (value.trim().isEmpty) {
        element.remove();
      } else {
        attr.remove();
      }
    }
  }

  static String _innerText(XmlNode node) {
    final buffer = StringBuffer();
    for (final child in node.children) {
      if (child is XmlText) {
        buffer.write(child.value);
      } else if (child is XmlElement) {
        final inner = _innerText(child);
        if (inner.trim().isNotEmpty) {
          buffer.write(inner);
          buffer.write('\n');
        }
      }
    }
    return buffer.toString();
  }

  static String _replacePlaceholders(String text, Map<String, String> variables) {
    return text.replaceAllMapped(RegExp(r'\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}'), (match) {
      final key = match.group(1)!;
      return variables[key] ?? '';
    });
  }
}
