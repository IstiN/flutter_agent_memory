/// Result of mapping new answers/notes to existing questions.
class QAMappingResult {
  final List<Mapping> mappings;

  const QAMappingResult({required this.mappings});

  factory QAMappingResult.fromJson(Map<String, dynamic> json) => QAMappingResult(
        mappings: (json['mappings'] as List? ?? [])
            .map((e) => Mapping.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'mappings': mappings.map((m) => m.toJson()).toList(),
      };
}

class Mapping {
  final String answerId;
  final String questionId;
  final double confidence;

  const Mapping({
    required this.answerId,
    required this.questionId,
    required this.confidence,
  });

  factory Mapping.fromJson(Map<String, dynamic> json) => Mapping(
        answerId: json['answerId'] as String? ?? '',
        questionId: json['questionId'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'answerId': answerId,
        'questionId': questionId,
        'confidence': confidence,
      };
}
