/// Normalizes a person name to a filesystem/obsidian identifier.
String normalizePersonName(String name) => name.replaceAll(RegExp(r'\s+'), '_');

/// Creates a slug from arbitrary text (lowercase, hyphen-separated).
String slugify(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
