import 'dart:convert';

import 'package:flutter_agent_memory/flutter_agent_memory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _questionMarkdown = '''
---
id: "q_0001"
type: "question"
author: "Alice"
date: "2024-01-01"
area: "dev"
topics: ["dart"]
tags: ["dart", "testing"]
---

# Question

How to test?
''';

MockClient _buildClient(
  Map<String, dynamic> responses,
  List<http.BaseRequest> requests,
) {
  return MockClient((request) async {
    requests.add(request);
    final key = '${request.method} ${request.url.path}';
    final response = responses[key];
    if (response == null) {
      return http.Response('not found', 404);
    }
    if (response is String) {
      return http.Response(response, 200);
    }
    return http.Response(jsonEncode(response), 200);
  });
}

MockClient _putGetClient(
  List<http.BaseRequest> requests,
  Map<String, dynamic> backend,
) {
  return MockClient((request) async {
    requests.add(request);
    if (request.method == 'PUT' &&
        request.url.path == '/kb/entities/question/q_0001') {
      backend['question/q_0001'] = request.body;
      return http.Response('ok', 200);
    }
    if (request.method == 'GET' &&
        request.url.path == '/kb/entities/question/q_0001') {
      return http.Response(
        backend['question/q_0001'] ?? 'not found',
        backend.containsKey('question/q_0001') ? 200 : 404,
      );
    }
    return http.Response('not found', 404);
  });
}

MockClient _fileClient(List<http.BaseRequest> requests) {
  return MockClient((request) async {
    requests.add(request);
    if (request.method == 'PUT' &&
        request.url.path == '/kb/files/stats%2Ftimeline.md') {
      return http.Response('ok', 200);
    }
    if (request.method == 'GET' &&
        request.url.path == '/kb/files/stats%2Ftimeline.md') {
      return http.Response('# Timeline', 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('HttpKbStorage', () {
    late List<http.BaseRequest> requests;
    late HttpKbStorage storage;

    setUp(() {
      requests = [];
    });

    test('PUTs entity and GETs it back', () async {
      final backend = <String, dynamic>{};
      storage = HttpKbStorage(
        'http://localhost/kb',
        client: _putGetClient(requests, backend),
      );

      await storage.writeEntity('question', 'q_0001', _questionMarkdown);
      final content = await storage.readEntity('question', 'q_0001');
      expect(content, _questionMarkdown);

      expect(requests, hasLength(2));
      expect(requests.first.method, 'PUT');
      expect(requests.last.method, 'GET');
    });

    test('DELETEs entity and returns null on 404', () async {
      storage = HttpKbStorage(
        'http://localhost/kb',
        client: _buildClient({'DELETE /kb/entities/question/q_0001': 'ok'}, requests),
      );

      await storage.deleteEntity('question', 'q_0001');
      final content = await storage.readEntity('question', 'q_0001');
      expect(content, isNull);
    });

    test('lists entity ids and file paths', () async {
      storage = HttpKbStorage(
        'http://localhost/kb',
        client: _buildClient({
          'GET /kb/entities/question': ['q_0001', 'q_0002'],
          'GET /kb/files': ['INDEX.md', 'stats/timeline.md'],
        }, requests),
      );

      final ids = await storage.listEntityIds('question');
      expect(ids, ['q_0001', 'q_0002']);

      final paths = await storage.listFilePaths('stats/');
      expect(paths, ['INDEX.md', 'stats/timeline.md']);
    });

    test('loads context from remote endpoint', () async {
      storage = HttpKbStorage(
        'http://localhost/kb',
        client: _buildClient({
          'GET /kb/context': {
            'existingPeople': ['Alice'],
            'existingTopics': ['dart'],
            'maxQuestionId': 2,
            'maxAnswerId': 1,
            'maxNoteId': 0,
            'existingQuestions': [
              {
                'id': 'q_0001',
                'author': 'Alice',
                'text': 'How to test?',
                'area': 'dev',
                'answered': false,
              },
            ],
          },
        }, requests),
      );

      final context = await storage.loadContext();
      expect(context.existingPeople, {'Alice'});
      expect(context.existingTopics, {'dart'});
      expect(context.maxQuestionId, 2);
      expect(context.maxAnswerId, 1);
      expect(context.existingQuestions, hasLength(1));
    });

    test('initializes remote backend', () async {
      storage = HttpKbStorage(
        'http://localhost/kb',
        client: _buildClient({'POST /kb/initialize': 'ok'}, requests),
      );

      await storage.initialize(clean: true);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.queryParameters['clean'], 'true');
    });

    test('reads and writes file by path', () async {
      storage = HttpKbStorage(
        'http://localhost/kb',
        client: _fileClient(requests),
      );

      await storage.writeFile('stats/timeline.md', '# Timeline');
      final content = await storage.readFile('stats/timeline.md');
      expect(content, '# Timeline');
    });

    test('describeLocation returns the entity URL', () {
      storage = HttpKbStorage('http://localhost/kb');
      expect(
        storage.describeLocation('question', 'q_0001'),
        'http://localhost/kb/entities/question/q_0001',
      );
    });
  });
}
