import 'dart:convert';
import 'dart:io';

/// Supported input type for the analysis pipeline.
enum InputType { text, image }

/// A single piece of input content loaded from disk or stdin.
class InputContent {
  final InputType type;
  final String sourcePath;
  final String? text;
  final String? imageDataUrl;

  const InputContent.text({required this.sourcePath, required this.text})
    : type = InputType.text,
      imageDataUrl = null;

  const InputContent.image({
    required this.sourcePath,
    required this.imageDataUrl,
  }) : type = InputType.image,
       text = null;

  /// Returns the text prompt that should be sent to the LLM alongside images.
  String get promptText =>
      text ?? 'Analyze the attached image(s) and extract knowledge.';

  /// Returns the image data URLs, if any.
  List<String>? get images =>
      type == InputType.image && imageDataUrl != null ? [imageDataUrl!] : null;
}

/// Loads input content for the analysis pipeline.
///
/// Supports:
/// - single text files (.txt, .md, .json, .yaml, .csv, .log, .dart, etc.)
/// - single image files (.png, .jpg, .jpeg, .gif, .webp, .bmp)
/// - directories containing supported files
/// - stdin (`-`)
class InputLoader {
  static const List<String> _textExtensions = [
    '.txt',
    '.md',
    '.markdown',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.log',
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.java',
    '.kt',
    '.swift',
    '.go',
    '.rs',
    '.sh',
    '.bash',
    '.zsh',
    '.xml',
    '.html',
    '.css',
    '.sql',
    '.graphql',
  ];

  static const List<String> _imageExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  ];

  /// Loads all supported inputs from [path].
  ///
  /// If [path] is `-`, returns a single text input read from stdin.
  /// If [path] is a directory, returns one input per supported file.
  /// If [path] is a file, returns a single input.
  Future<List<InputContent>> load(String path) async {
    if (path == '-') {
      final text = await stdin.transform(const SystemEncoding().decoder).join();
      return [InputContent.text(sourcePath: 'stdin', text: text)];
    }

    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      return _loadDirectory(Directory(path));
    }

    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('Input not found: $path');
    }
    final content = await _loadFile(file);
    return content != null ? [content] : const [];
  }

  List<InputContent> _loadDirectory(Directory dir) {
    final results = <InputContent>[];
    for (final file in dir.listSync().whereType<File>().where(_isSupported)) {
      final content = _loadFileSync(file);
      if (content != null) results.add(content);
    }
    return results..sort((a, b) => a.sourcePath.compareTo(b.sourcePath));
  }

  Future<InputContent?> _loadFile(File file) async => _loadFileSync(file);

  InputContent? _loadFileSync(File file) {
    final ext = _extension(file.path);
    if (_textExtensions.contains(ext)) {
      return InputContent.text(
        sourcePath: file.path,
        text: file.readAsStringSync(),
      );
    }
    if (_imageExtensions.contains(ext)) {
      final bytes = file.readAsBytesSync();
      final mime = _mimeType(ext);
      final base64 = base64Encode(bytes);
      return InputContent.image(
        sourcePath: file.path,
        imageDataUrl: 'data:$mime;base64,$base64',
      );
    }
    return null;
  }

  bool _isSupported(File file) {
    final ext = _extension(file.path);
    return _textExtensions.contains(ext) || _imageExtensions.contains(ext);
  }

  String _extension(String path) {
    final idx = path.lastIndexOf('.');
    return idx == -1 ? '' : path.substring(idx).toLowerCase();
  }

  String _mimeType(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      default:
        return 'image/png';
    }
  }
}
