/// Normalizes a person name for wikilinks (spaces → underscores, preserves case).
String normalizePersonName(String name) => name.replaceAll(RegExp(r'\s+'), '_');

/// Normalizes a person name for filesystem paths (lowercase, spaces → underscores).
String personFileId(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');

/// Creates a slug from arbitrary text (lowercase, hyphen-separated).
String slugify(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
