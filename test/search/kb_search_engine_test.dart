import 'dart:io';

import 'package:flutter_agent_memory/src/search/kb_search_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late KBSearchEngine engine;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('kb_search_');
    engine = KBSearchEngine(tmpDir);

    Directory('${tmpDir.path}/questions').createSync(recursive: true);
    Directory('${tmpDir.path}/answers').createSync(recursive: true);

    File('${tmpDir.path}/questions/q_0001.md').writeAsStringSync('''
---
id: "q_0001"
type: "question"
author: "Alice"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["unit-tests", "dart"]
---

# Question

How to test?
''');

    File('${tmpDir.path}/questions/q_0002.md').writeAsStringSync('''
---
id: "q_0002"
type: "question"
author: "Bob"
date: "2024-01-01"
area: "dev"
topics: ["flutter"]
tags: ["widgets", "flutter"]
---

# Question

How to build widgets?
''');

    File('${tmpDir.path}/answers/a_0001.md').writeAsStringSync('''
---
id: "a_0001"
type: "answer"
author: "Charlie"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["dart", "test-package"]
quality: 0.9
---

# Answer

Use the test package.
''');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('finds records matching all requested tags', () {
    final results = engine.searchByTags(['dart', 'unit-tests']);
    expect(results.length, 1);
    expect(results.first.id, 'q_0001');
    expect(results.first.matchedTags, containsAll(['dart', 'unit-tests']));
  });

  test('finds records matching any requested tag when matchAll=false', () {
    final results = engine.searchByTags(['unit-tests', 'widgets'], matchAll: false);
    final ids = results.map((r) => r.id).toSet();
    expect(ids, containsAll(['q_0001', 'q_0002']));
  });

  test('filters by entity type', () {
    final results = engine.searchByTags(['dart'], entityTypes: ['answer']);
    expect(results.length, 1);
    expect(results.first.entityType, 'answer');
    expect(results.first.id, 'a_0001');
  });

  test('returns empty list for unknown tags', () {
    final results = engine.searchByTags(['kubernetes']);
    expect(results, isEmpty);
  });

  test('case-insensitive matching', () {
    final results = engine.searchByTags(['DART', 'UNIT-TESTS']);
    expect(results.length, 1);
    expect(results.first.id, 'q_0001');
  });

  test('ranks frequently accessed and important records higher', () {
    Directory('${tmpDir.path}/notes').createSync(recursive: true);
    File('${tmpDir.path}/questions/q_0003.md').writeAsStringSync('''
---
id: "q_0003"
type: "question"
author: "Alice"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["dart"]
accessCount: 10
importance: 0.9
lastAccessedAt: "2024-06-01T00:00:00Z"
---

# Question

Popular dart question.
''');

    final results = engine.searchByTags(['dart'], matchAll: false);
    expect(results.first.id, 'q_0003');
  });
}
