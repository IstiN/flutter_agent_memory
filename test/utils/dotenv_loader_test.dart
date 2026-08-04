import 'dart:io';

import 'package:flutter_agent_memory/src/utils/dotenv_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('dotenv_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('returns empty map for missing file', () {
    expect(loadDotEnv('${tmpDir.path}/missing.env'), isEmpty);
  });

  test('parses key value pairs', () {
    final file = File('${tmpDir.path}/.env')
      ..writeAsStringSync('KEY=value\nFOO=bar\n');
    expect(loadDotEnv(file.path), {'KEY': 'value', 'FOO': 'bar'});
  });

  test('ignores comments and blank lines', () {
    final file = File('${tmpDir.path}/.env')
      ..writeAsStringSync('# comment\n\nKEY=value\n# another\nFOO=bar');
    expect(loadDotEnv(file.path), {'KEY': 'value', 'FOO': 'bar'});
  });

  test('ignores lines without equals', () {
    final file = File('${tmpDir.path}/.env')..writeAsStringSync('NO_EQUALS\nKEY=value');
    expect(loadDotEnv(file.path), {'KEY': 'value'});
  });

  test('trims keys and values', () {
    final file = File('${tmpDir.path}/.env')..writeAsStringSync('  KEY  =  value  ');
    expect(loadDotEnv(file.path), {'KEY': 'value'});
  });
}
