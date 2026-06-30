import 'dart:convert';
import 'dart:io';

import '../agents/kb_aggregation_agent.dart';
import '../agents/kb_analysis_agent.dart';
import '../agents/kb_qa_mapping_agent.dart';
import '../llm/llm_provider.dart';
import '../models/kb_processing_mode.dart';
import '../models/kb_result.dart';
import '../storage/kb_context_loader.dart';
import '../storage/kb_structure_manager.dart';
import '../storage/source_config_manager.dart';
import '../utils/frontmatter.dart';
import 'kb_analysis_validator.dart';
import 'kb_orchestrator_params.dart';
import 'kb_qa_mapping_service.dart';

/// Main coordinator for building and updating the knowledge base.
class KBOrchestrator {
  final LlmProvider provider;
  final KBAnalysisAgent _analysisAgent;
  final KBAggregationAgent _aggregationAgent;
  final KBQAMappingService _qaMappingService;
  final KBStructureManager _structureManager;
  final KBContextLoader _contextLoader;
  final KBAnalysisValidator _validator;
  final SourceConfigManager _sourceConfigManager;

  KBOrchestrator(this.provider)
    : _analysisAgent = KBAnalysisAgent(provider),
      _aggregationAgent = KBAggregationAgent(provider),
      _qaMappingService = KBQAMappingService(
        KBQuestionAnswerMappingAgent(provider),
      ),
      _structureManager = KBStructureManager(),
      _contextLoader = KBContextLoader(),
      _validator = KBAnalysisValidator(),
      _sourceConfigManager = SourceConfigManager();

  /// Runs the full pipeline.
  Future<KBResult> run(KBOrchestratorParams params) async {
    final outputDir = Directory(params.outputPath);
    _contextLoader.initializeOutputDirectories(
      outputDir,
      clean: params.cleanOutput,
    );

    // Save raw input. Skip binary images.
    if (params.inputText.isNotEmpty && params.inputImages.isEmpty) {
      final rawFile = File(
        '${outputDir.path}/inbox/raw/${params.sourceName}.md',
      );
      rawFile.writeAsStringSync(params.inputText);
    }

    final context = _contextLoader.loadContext(outputDir);

    final analysis = await _analysisAgent.analyze(
      params.inputText,
      context,
      sourceName: params.sourceName,
      extraInstructions: params.analysisExtraInstructions,
      images: params.inputImages.isNotEmpty ? params.inputImages : null,
    );

    _validator.validateAndClean(analysis);

    if (params.processingMode != KBProcessingMode.aggregateOnly) {
      await _qaMappingService.applyMapping(
        analysis,
        context,
        extraInstructions: params.qaMappingExtraInstructions,
      );
    }

    // Persist the raw AI result for traceability.
    final analyzedFile = File(
      '${outputDir.path}/inbox/analyzed/${params.sourceName}_analyzed.json',
    );
    analyzedFile.writeAsStringSync(jsonEncode(analysis.toJson()));

    final mappedAnalysis = _structureManager.mapIds(analysis, context);
    final personContributions = _structureManager
        .collectPersonContributionsFromAnalysis(mappedAnalysis);
    _structureManager.buildStructure(
      mappedAnalysis,
      outputDir,
      params.sourceName,
      personContributions,
    );

    if (params.processingMode == KBProcessingMode.full) {
      await _runAggregation(outputDir, params);
    }

    _structureManager.generateIndexes(outputDir);
    _sourceConfigManager.updateLastSyncDate(params.sourceName, outputDir);

    return _structureManager.buildResult(mappedAnalysis, outputDir);
  }

  /// Regenerates structure files from existing Q/A/N on disk.
  Future<KBResult> regenerateStructureFromExistingFiles(
    String outputPath,
    String sourceName,
  ) async {
    final outputDir = Directory(outputPath);
    _structureManager.rebuildPeopleProfiles(outputDir, sourceName);
    _structureManager.generateIndexes(outputDir);
    return KBResult(
      success: true,
      message: 'Regeneration completed',
      peopleCount: _countPeople(outputDir),
      topicsCount: _countTopics(outputDir),
      areasCount: _countAreas(outputDir),
    );
  }

  Future<void> _runAggregation(
    Directory outputDir,
    KBOrchestratorParams params,
  ) async {
    await _aggregatePeople(outputDir, params);
    await _aggregateTopics(outputDir, params);
    await _aggregateAreas(outputDir, params);
  }

  Future<void> _aggregatePeople(
    Directory outputDir,
    KBOrchestratorParams params,
  ) async {
    final peopleDir = Directory('${outputDir.path}/people');
    if (!peopleDir.existsSync()) return;

    for (final dir in peopleDir.listSync().whereType<Directory>()) {
      final personId = dir.uri.pathSegments.reversed.firstWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (personId.isEmpty) continue;
      final profileFile = File('${dir.path}/$personId.md');
      final descFile = File('${dir.path}/$personId-desc.md');
      if (!profileFile.existsSync()) continue;

      try {
        final fm = parseFrontmatter(profileFile.readAsStringSync());
        final name = fm.getString('name') ?? personId;
        final questionsAsked = fm.getString('questionsAsked') ?? '0';
        final answersProvided = fm.getString('answersProvided') ?? '0';
        final notesContributed = fm.getString('notesContributed') ?? '0';
        final body = extractBody(profileFile.readAsStringSync());

        final data =
            '''
name: $name
questionsAsked: $questionsAsked
answersProvided: $answersProvided
notesContributed: $notesContributed
Contributions:
$body
''';
        final description = await _aggregationAgent.aggregate(
          'person',
          personId,
          data,
          extraInstructions: params.aggregationExtraInstructions,
        );
        _writeDescFile(descFile, description);
      } catch (_) {}
    }
  }

  Future<void> _aggregateTopics(
    Directory outputDir,
    KBOrchestratorParams params,
  ) async {
    final topicsDir = Directory('${outputDir.path}/topics');
    if (!topicsDir.existsSync()) return;

    for (final file in topicsDir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.md') && !f.path.endsWith('-desc.md'),
    )) {
      final id = file.uri.pathSegments.last.replaceAll('.md', '');
      final descFile = File('${topicsDir.path}/$id-desc.md');
      try {
        final fm = parseFrontmatter(file.readAsStringSync());
        final title = fm.getString('title') ?? id;
        final body = extractBody(file.readAsStringSync());
        final data =
            '''
title: $title
Content:
$body
''';
        final description = await _aggregationAgent.aggregate(
          'topic',
          id,
          data,
          extraInstructions: params.aggregationExtraInstructions,
        );
        _writeDescFile(descFile, description);
      } catch (_) {}
    }
  }

  Future<void> _aggregateAreas(
    Directory outputDir,
    KBOrchestratorParams params,
  ) async {
    final areasDir = Directory('${outputDir.path}/areas');
    if (!areasDir.existsSync()) return;

    for (final dir in areasDir.listSync().whereType<Directory>()) {
      final areaId = dir.uri.pathSegments.reversed.firstWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (areaId.isEmpty) continue;
      final areaFile = File('${dir.path}/$areaId.md');
      final descFile = File('${dir.path}/$areaId-desc.md');
      if (!areaFile.existsSync()) continue;

      try {
        final fm = parseFrontmatter(areaFile.readAsStringSync());
        final title = fm.getString('title') ?? areaId;
        final body = extractBody(areaFile.readAsStringSync());
        final data =
            '''
title: $title
Content:
$body
''';
        final description = await _aggregationAgent.aggregate(
          'area',
          areaId,
          data,
          extraInstructions: params.aggregationExtraInstructions,
        );
        _writeDescFile(descFile, description);
      } catch (_) {}
    }
  }

  void _writeDescFile(File descFile, String description) {
    descFile.writeAsStringSync(
      '<!-- AI_CONTENT_START -->\n\n$description\n\n<!-- AI_CONTENT_END -->\n',
    );
  }

  int _countPeople(Directory dir) {
    final d = Directory('${dir.path}/people');
    return d.existsSync() ? d.listSync().whereType<Directory>().length : 0;
  }

  int _countTopics(Directory dir) {
    final d = Directory('${dir.path}/topics');
    return d.existsSync()
        ? d
              .listSync()
              .whereType<File>()
              .where(
                (f) => f.path.endsWith('.md') && !f.path.endsWith('-desc.md'),
              )
              .length
        : 0;
  }

  int _countAreas(Directory dir) {
    final d = Directory('${dir.path}/areas');
    return d.existsSync() ? d.listSync().whereType<Directory>().length : 0;
  }
}
