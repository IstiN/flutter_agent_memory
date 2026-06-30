import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/kb_context.dart';
import 'kb_storage.dart';

/// HTTP-backed implementation of [KbStorage].
///
/// Talks to a remote knowledge-base server using a small REST convention:
///
/// - `GET    /entities/{type}/{id}`       -> read entity
/// - `PUT    /entities/{type}/{id}`       -> write entity (body = Markdown)
/// - `DELETE /entities/{type}/{id}`       -> delete entity
/// - `GET    /entities/{type}`            -> JSON list of ids
/// - `GET    /files/{path}`               -> read structure file
/// - `PUT    /files/{path}`               -> write structure file
/// - `GET    /context`                    -> JSON context
/// - `POST   /initialize?clean={true|false}` -> initialize/clean backend
///
/// The exact URL layout can be changed by subclassing and overriding the
/// `_url` helpers.
class HttpKbStorage implements KbStorage {
  final Uri baseUrl;
  final Map<String, String> headers;
  final http.Client _client;

  HttpKbStorage(
    String baseUrl, {
    Map<String, String>? headers,
    http.Client? client,
  }) : baseUrl = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), '')),
       headers = headers ?? const {},
       _client = client ?? http.Client();

  @override
  FutureOr<void> initialize({bool clean = false}) async {
    await _request(
      'POST',
      _url('initialize', query: {'clean': clean.toString()}),
    );
  }

  @override
  Future<KBContext> loadContext() async {
    final response = await _request('GET', _url('context'));
    final body = _decode(response);
    final json = (body is Map<String, dynamic>) ? body : <String, dynamic>{};

    final context = KBContext(
      existingPeople: _stringSet(json['existingPeople']),
      existingTopics: _stringSet(json['existingTopics']),
      maxQuestionId: _int(json['maxQuestionId']),
      maxAnswerId: _int(json['maxAnswerId']),
      maxNoteId: _int(json['maxNoteId']),
    );

    final questions = json['existingQuestions'];
    if (questions is List) {
      for (final q in questions) {
        if (q is! Map<String, dynamic>) continue;
        context.existingQuestions.add(
          QuestionSummary(
            id: q['id'] as String? ?? '',
            author: q['author'] as String? ?? '',
            text: q['text'] as String? ?? '',
            area: q['area'] as String? ?? '',
            answered: q['answered'] as bool? ?? false,
          ),
        );
      }
    }

    return context;
  }

  @override
  Future<String?> readEntity(String type, String id) async {
    final response = await _request(
      'GET',
      _url('entities/$type/$id'),
      throwOn404: false,
    );
    return response == null ? null : _body(response);
  }

  @override
  Future<void> writeEntity(String type, String id, String content) async {
    await _request('PUT', _url('entities/$type/$id'), body: content);
  }

  @override
  Future<void> deleteEntity(String type, String id) async {
    await _request('DELETE', _url('entities/$type/$id'));
  }

  @override
  Future<List<String>> listEntityIds(String type) async {
    final response = await _request('GET', _url('entities/$type'));
    final body = _decode(response);
    if (body is List) {
      return body.map((e) => e.toString()).toList();
    }
    return const [];
  }

  @override
  Future<String?> readFile(String path) async {
    final response = await _request(
      'GET',
      _url('files/${Uri.encodeComponent(path)}'),
      throwOn404: false,
    );
    return response == null ? null : _body(response);
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await _request(
      'PUT',
      _url('files/${Uri.encodeComponent(path)}'),
      body: content,
    );
  }

  @override
  Future<List<String>> listFilePaths(String prefix) async {
    final response = await _request(
      'GET',
      _url('files', query: {'prefix': prefix}),
    );
    final body = _decode(response);
    if (body is List) {
      return body.map((e) => e.toString()).toList();
    }
    return const [];
  }

  @override
  String describeLocation(String type, String id) =>
      _url('entities/$type/$id').toString();

  Uri _url(String path, {Map<String, String>? query}) {
    return baseUrl.replace(
      path: '${baseUrl.path}/$path',
      queryParameters: query,
    );
  }

  Future<http.Response?> _request(
    String method,
    Uri url, {
    String? body,
    bool throwOn404 = true,
  }) async {
    final request = http.Request(method, url);
    request.headers.addAll(headers);
    if (body != null) {
      request.body = body;
      request.headers['Content-Type'] = 'text/markdown; charset=utf-8';
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 404 && !throwOn404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'HTTP $method $url failed: ${response.statusCode} ${response.body}',
      );
    }
    return response;
  }

  String _body(http.Response response) => utf8.decode(response.bodyBytes);

  dynamic _decode(http.Response? response) {
    if (response == null) return null;
    final text = _body(response).trim();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  Set<String> _stringSet(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toSet();
    return const <String>{};
  }

  int _int(dynamic value) =>
      value is int ? value : (value is String ? int.tryParse(value) ?? 0 : 0);
}
