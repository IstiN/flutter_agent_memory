import '../models/link.dart';

/// Parses a JSON value into a list of strings.
List<String> stringListFromJson(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  return const <String>[];
}

/// Parses a JSON value into a list of [Link]s.
List<Link> linkListFromJson(dynamic value) {
  if (value is List)
    return value.map((e) => Link.fromJson(e as Map<String, dynamic>)).toList();
  return const <Link>[];
}
