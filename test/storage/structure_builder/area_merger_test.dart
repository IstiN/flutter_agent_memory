import 'dart:io';

import 'package:flutter_agent_memory/src/models/analysis_result.dart';
import 'package:flutter_agent_memory/src/models/answer.dart';
import 'package:flutter_agent_memory/src/models/note.dart';
import 'package:flutter_agent_memory/src/models/question.dart';
import 'package:flutter_agent_memory/src/storage/structure_builder/area_merger.dart';
import 'package:test/test.dart';

String _path(Directory dir) => dir.path;

void main() {
  late Directory tmpDir;
  late AreaMerger merger;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('area_merger_');
    merger = const AreaMerger(path: _path);
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('collects contributors and topics from analysis', () {
    final result = merger.merge(
      AnalysisResult(
        questions: [
          Question(
            id: 'q_1',
            author: 'Alice',
            text: 'Q?',
            date: '2024-01-01',
            area: 'dev',
            topics: ['dart'],
            tags: const [],
            answeredBy: '',
            links: const [],
          ),
        ],
        answers: [
          Answer(
            id: 'a_1',
            author: 'Bob',
            text: 'A.',
            date: '2024-01-01',
            area: 'dev',
            topics: const ['dart', 'testing'],
            tags: const [],
            quality: 1.0,
            links: const [],
          ),
        ],
        notes: [
          Note(
            id: 'n_1',
            author: 'Carol',
            text: 'N.',
            date: '2024-01-01',
            area: 'ops',
            topics: const ['k8s'],
            tags: const [],
            answersQuestions: const [],
            links: const [],
          ),
        ],
      ),
      tmpDir,
      'src',
    );

    expect(result.areaContributors['dev'], {'Alice', 'Bob'});
    expect(result.areaContributors['ops'], {'Carol'});
    expect(result.areaTopics['dev'], {'dart', 'testing'});
    expect(result.areaTopics['ops'], {'k8s'});
    expect(result.sourceToAdd('dev'), 'src');
  });

  test('merges contributors from existing area file', () {
    final areaDir = Directory('${tmpDir.path}/areas/dev')..createSync(recursive: true);
    File('${areaDir.path}/dev.md').writeAsStringSync('''---
type: area
title: dev
id: dev
sources: []
contributors: ["Eve"]
created: 2024-01-01T00:00:00Z
---

# dev

![[dev-desc]]
''');

    final result = merger.merge(
      AnalysisResult(
        questions: [
          Question(
            id: 'q_1',
            author: 'Alice',
            text: 'Q?',
            date: '2024-01-01',
            area: 'dev',
            topics: const ['dart'],
            tags: const [],
            answeredBy: '',
            links: const [],
          ),
        ],
        answers: [],
        notes: [],
      ),
      tmpDir,
      'src',
    );

    expect(result.areaContributors['dev'], {'Alice', 'Eve'});
  });

  test('merges topic links from existing area file', () {
    final areaDir = Directory('${tmpDir.path}/areas/dev')..createSync(recursive: true);
    File('${areaDir.path}/dev.md').writeAsStringSync('''---
type: area
title: dev
id: dev
sources: []
contributors: []
created: 2024-01-01T00:00:00Z
---

# dev

![[dev-desc]]

## Topics

- [[flutter|Flutter]]

<!-- AUTO_GENERATED_START -->
<!-- AUTO_GENERATED_END -->
''');

    final result = merger.merge(
      AnalysisResult(
        questions: [
          Question(
            id: 'q_1',
            author: 'Alice',
            text: 'Q?',
            date: '2024-01-01',
            area: 'dev',
            topics: const ['dart'],
            tags: const [],
            answeredBy: '',
            links: const [],
          ),
        ],
        answers: [],
        notes: [],
      ),
      tmpDir,
      'src',
    );

    expect(result.areaTopics['dev'], {'dart', 'Flutter'});
  });
}
