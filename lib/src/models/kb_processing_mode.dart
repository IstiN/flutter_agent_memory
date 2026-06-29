enum KBProcessingMode {
  /// Analyze, build structure, and generate AI descriptions.
  full,

  /// Analyze and build structure without AI descriptions.
  processOnly,

  /// Generate AI descriptions for an existing knowledge base.
  aggregateOnly,
}

extension KBProcessingModeParsing on KBProcessingMode {
  static KBProcessingMode fromString(String value) {
    switch (value.toLowerCase().replaceAll('_', '').replaceAll('-', '')) {
      case 'processonly':
      case 'process':
        return KBProcessingMode.processOnly;
      case 'aggregateonly':
      case 'aggregate':
        return KBProcessingMode.aggregateOnly;
      case 'full':
      default:
        return KBProcessingMode.full;
    }
  }
}
