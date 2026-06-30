import 'dart:async';

import 'package:xml/xml.dart';

import 'prompt_loader_default.dart'
    if (dart.library.html) 'prompt_loader_default_stub.dart';

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
///
/// On non-VM platforms the default file-based loader is unavailable. Call
/// [setLoader] at startup to inject a host-provided loader (for example,
/// Flutter's `rootBundle.loadString`).
class PromptLoader {
  static final Map<String, String> _cache = {};
  static Future<String> Function(String name)? _loader;

  /// Overrides the default prompt loader.
  ///
  /// The callback receives the XML file name (e.g. `kb_analysis.xml`) and
  /// should return its raw content.
  static void setLoader(Future<String> Function(String name) loader) {
    _loader = loader;
    _cache.clear();
  }

  static Future<String> Function(String name) get _defaultLoader => loadPromptFile;

  /// Loads and renders the prompt named [name] (e.g. `kb_analysis.xml`).
  ///
  /// [variables] are substituted for `${key}` placeholders. Missing variables
  /// are replaced with an empty string.
  static Future<String> load(String name, Map<String, String> variables) async {
    final cached = _cache[name];
    if (cached != null) {
      return _render(cached, variables);
    }

    final raw = await (_loader ?? _defaultLoader)(name);
    _cache[name] = raw;
    return _render(raw, variables);
  }

  /// Synchronous version is not supported on all platforms.
  ///
  /// Use [load] instead. This method is kept for API compatibility and will
  /// throw on platforms where the default loader is asynchronous.
  static String loadSync(String name, Map<String, String> variables) {
    final cached = _cache[name];
    if (cached != null) {
      return _render(cached, variables);
    }
    throw UnsupportedError(
      'PromptLoader.loadSync is not supported on this platform. Use load().',
    );
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

  static void _processConditionals(
    XmlNode node,
    Map<String, String> variables,
  ) {
    for (final element in List<XmlElement>.from(node.descendantElements)) {
      final attr = element.attributes.cast<XmlAttribute?>().firstWhere(
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

  static String _replacePlaceholders(
    String text,
    Map<String, String> variables,
  ) {
    return text.replaceAllMapped(RegExp(r'\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}'), (
      match,
    ) {
      final key = match.group(1)!;
      return variables[key] ?? '';
    });
  }
}
