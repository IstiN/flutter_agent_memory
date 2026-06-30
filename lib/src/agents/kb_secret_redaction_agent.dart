import 'package:meta/meta.dart';

/// Redacts common secret patterns from text before it is stored in the
/// knowledge base.
///
/// Inspired by Codex memory hygiene rules: tokens, keys, and passwords must
/// never be persisted verbatim.
class KBSecretRedactionAgent {
  /// Shared redaction marker. Keeping it stable makes it easy to grep for
  /// redacted content later.
  static const redacted = '[REDACTED_SECRET]';

  /// Regexes ordered from most specific to most generic.
  static final List<RegExp> _patterns = [
    // Private / SSH / PEM keys.
    RegExp(
      r'-----BEGIN (RSA |OPENSSH |EC |DSA |ED25519 )?PRIVATE KEY-----[\s\S]*?-----END (RSA |OPENSSH |EC |DSA |ED25519 )?PRIVATE KEY-----',
      caseSensitive: false,
    ),
    // OpenAI-style API keys.
    RegExp(r'\bsk-[a-zA-Z0-9]{20,}\b'),
    // GitHub personal access tokens.
    RegExp(r'\bgh[pousr]_[a-zA-Z0-9]{36}\b'),
    // AWS access key ids.
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
    // AWS secret access keys (base64-ish 40 chars).
    RegExp(r'\b[A-Za-z0-9/+=]{40}\b'),
    // Generic bearer tokens.
    RegExp(r'\bBearer\s+[a-zA-Z0-9_\-\.]{20,}\b', caseSensitive: false),
    // Assignment-style secrets.
    RegExp(
      r'\b(api[_-]?key|apikey|auth[_-]?token|access[_-]?token|password|passwd|pwd|secret|client[_-]?secret)\s*[:=]\s*\S+',
      caseSensitive: false,
    ),
    // URLs with credentials.
    RegExp(r'\b\w+://[^\s:@]+:[^\s@]+@[^\s]+'),
  ];

  /// Redacts known secret patterns in [text].
  static String redact(String text) {
    var result = text;
    for (final pattern in _patterns) {
      result = result.replaceAllMapped(pattern, (_) => redacted);
    }
    return result;
  }

  @visibleForTesting
  static List<RegExp> get patterns => _patterns;
}
