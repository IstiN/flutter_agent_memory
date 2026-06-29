import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_agent_memory/src/utils/input_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late InputLoader loader;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('input_loader_');
    loader = InputLoader();
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('loads a text file', () async {
    final file = File('${tmpDir.path}/notes.md');
    file.writeAsStringSync('This is a note.');

    final inputs = await loader.load(file.path);
    expect(inputs.length, 1);
    expect(inputs.first.type, InputType.text);
    expect(inputs.first.text, 'This is a note.');
  });

  test('loads an image file as base64 data URL', () async {
    final file = File('${tmpDir.path}/diagram.png');
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    file.writeAsBytesSync(bytes);

    final inputs = await loader.load(file.path);
    expect(inputs.length, 1);
    expect(inputs.first.type, InputType.image);
    expect(inputs.first.imageDataUrl, startsWith('data:image/png;base64,'));
    expect(inputs.first.images, hasLength(1));
  });

  test('loads all supported files from a directory', () async {
    File('${tmpDir.path}/a.md').writeAsStringSync('text a');
    File('${tmpDir.path}/b.txt').writeAsStringSync('text b');
    File('${tmpDir.path}/c.png').writeAsBytesSync(Uint8List.fromList([0x89, 0x50]));
    File('${tmpDir.path}/ignored.exe').writeAsBytesSync(Uint8List.fromList([0x00]));

    final awaited = await loader.load(tmpDir.path);
    expect(awaited.length, 3);
    expect(awaited.where((i) => i.type == InputType.text).length, 2);
    expect(awaited.where((i) => i.type == InputType.image).length, 1);
  });
}
