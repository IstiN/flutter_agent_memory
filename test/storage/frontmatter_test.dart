import 'package:flutter_agent_memory/src/utils/frontmatter.dart';
import 'package:test/test.dart';

void main() {
  test('parses string and list values', () {
    final content = '''---
id: "q_0001"
type: "question"
topics: ["docker-build", "ci-cd"]
tags: ["docker", "buildkit"]
answered: true
quality: 0.85
---
# Body
''';  // Corrected: removed stray `
    final fm = parseFrontmatter(content);
    expect(fm.getString('id'), 'q_0001');
    expect(fm.getStringList('topics'), ['docker-build', 'ci-cd']);
    expect(fm.getStringList('tags'), ['docker', 'buildkit']);
    expect(fm.getBool('answered'), isTrue);
    expect(fm.getDouble('quality'), closeTo(0.85, 0.001));
  });

  test('serializes frontmatter', () {
    final fm = Frontmatter()
      ..['id'] = 'q_0001'
      ..['type'] = 'question'
      ..['topics'] = ['docker-build']
      ..['tags'] = ['docker', 'buildkit']
      ..['quality'] = 0.85;
    final yaml = fm.serialize();
    expect(yaml, contains('id: "q_0001"'));
    expect(yaml, contains('type: "question"'));
    expect(yaml, contains('topics: ["docker-build"]'));
    expect(yaml, contains('tags: ["docker", "buildkit"]'));
    expect(yaml, contains('quality: 0.85'));
  });

  test('extracts body without frontmatter', () {
    final content = '---\nid: "a_0001"\n---\n\n# Answer\n\nSome text.';
    expect(extractBody(content), '# Answer\n\nSome text.');
  });
}
