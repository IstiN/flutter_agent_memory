/// A URL reference embedded in a question, answer, or note.
class Link {
  final String url;
  final String title;

  const Link({required this.url, required this.title});

  factory Link.fromJson(Map<String, dynamic> json) => Link(
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'url': url, 'title': title};

  Link copyWith({String? url, String? title}) =>
      Link(url: url ?? this.url, title: title ?? this.title);

  @override
  String toString() => 'Link(url: $url, title: $title)';
}
