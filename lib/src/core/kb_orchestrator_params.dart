import '../models/kb_processing_mode.dart';

/// Parameters for the knowledge-base orchestrator.
class KBOrchestratorParams {
  final String sourceName;
  final String inputText;
  final List<String> inputImages;
  final String outputPath;
  final KBProcessingMode processingMode;
  final String analysisExtraInstructions;
  final String aggregationExtraInstructions;
  final String qaMappingExtraInstructions;
  final bool cleanOutput;

  const KBOrchestratorParams({
    required this.sourceName,
    required this.inputText,
    this.inputImages = const [],
    required this.outputPath,
    this.processingMode = KBProcessingMode.full,
    this.analysisExtraInstructions = '',
    this.aggregationExtraInstructions = '',
    this.qaMappingExtraInstructions = '',
    this.cleanOutput = false,
  });
}
