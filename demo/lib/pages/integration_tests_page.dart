import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';

/// A set of runnable integration/smoke tests against the currently selected
/// LLM provider/model configured in Settings.
class IntegrationTestsPage extends StatefulWidget {
  final KbService kbService;

  const IntegrationTestsPage({super.key, required this.kbService});

  @override
  State<IntegrationTestsPage> createState() => _IntegrationTestsPageState();
}

class _IntegrationTestsPageState extends State<IntegrationTestsPage> {
  final List<_TestResult> _results = [];
  bool _runningAll = false;

  static const _testTimeout = Duration(seconds: 120);

  List<_TestDefinition> get _tests => [
    _TestDefinition(
      id: 'ping',
      name: 'Simple chat ping',
      description:
          'Sends a tiny prompt and checks that the model returns a non-empty response.',
      run: _runPing,
      timeout: _testTimeout,
    ),
    _TestDefinition(
      id: 'json',
      name: 'JSON output',
      description:
          'Asks the model to return strict JSON and verifies it parses.',
      run: _runJson,
      timeout: _testTimeout,
    ),
    _TestDefinition(
      id: 'tags',
      name: 'Tag generator',
      description:
          'Runs the KB tag generator for a query and checks it returns relevant tags.',
      run: _runTagGenerator,
      timeout: _testTimeout,
    ),
    _TestDefinition(
      id: 'analysis',
      name: 'Raw text analysis',
      description:
          'Analyzes a short conversation and checks that at least one question is extracted.',
      run: _runAnalysis,
      timeout: _testTimeout,
    ),
    _TestDefinition(
      id: 'search',
      name: 'Search pipeline',
      description:
          'Adds a sample record, searches by text, and checks the result is found.',
      run: _runSearchPipeline,
      timeout: _testTimeout,
    ),
  ];

  @override
  void initState() {
    super.initState();
    for (final t in _tests) {
      _results.add(_TestResult(t.id));
    }
  }

  LlmProvider? get _provider => widget.kbService.providerService.provider;

  String get _providerLabel {
    final settings = widget.kbService.settings;
    if (settings.model.isEmpty) return 'No model selected';
    return '${settings.provider} / ${settings.model}';
  }

  Future<void> _runAll() async {
    setState(() => _runningAll = true);
    try {
      for (var i = 0; i < _tests.length; i++) {
        await _runTestAt(i);
      }
    } finally {
      setState(() => _runningAll = false);
    }
  }

  Future<void> _runTestAt(int index) async {
    final test = _tests[index];
    final result = _results[index];
    setState(() {
      result.status = _Status.running;
      result.message = null;
      result.duration = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final output = await test.run(_provider!).timeout(
        test.timeout,
        onTimeout: () {
          throw TimeoutException(
            '${test.name} did not complete within '
            '${test.timeout.inSeconds}s',
          );
        },
      );
      stopwatch.stop();
      setState(() {
        result.status = _Status.passed;
        result.message = output;
        result.duration = stopwatch.elapsed;
      });
    } catch (e, s) {
      stopwatch.stop();
      setState(() {
        result.status = _Status.failed;
        result.message = '$e\n$s';
        result.duration = stopwatch.elapsed;
      });
    }
  }

  Future<String> _runPing(LlmProvider provider) async {
    final response = await provider.chat(
      'Reply with exactly one word: hello.',
    );
    final text = response.trim();
    if (text.isEmpty) throw StateError('Empty response from model');
    return 'Response: "$text"';
  }

  Future<String> _runJson(LlmProvider provider) async {
    final response = await provider.chat(
      'Return ONLY a JSON object with a single boolean field named "ok" set to true. '
      'No markdown, no explanation.',
    );
    final text = response.trim();
    final cleaned = text
        .replaceAll(RegExp(r'^```json\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
    final json = jsonDecode(cleaned) as Map<String, dynamic>;
    if (json['ok'] != true) throw StateError('Expected {"ok": true}, got $json');
    return 'Parsed JSON: $json';
  }

  Future<String> _runTagGenerator(LlmProvider provider) async {
    final agent = KBTagGeneratorAgent(provider);
    final tags = await agent.generateTags(
      'Flutter state management with Riverpod',
      existingTags: {
        'flutter',
        'state',
        'riverpod',
        'provider',
        'bloc',
        'architecture',
      },
      maxTags: 5,
    );
    if (tags.isEmpty) throw StateError('No tags generated');
    return 'Generated tags: ${tags.join(', ')}';
  }

  Future<String> _runAnalysis(LlmProvider provider) async {
    final service = widget.kbService.rawTextProcessor;
    final result = await service.process(
      'Alice: How do I test Dart code?\nBob: Use the test package.',
    );
    final questions = (result['questions'] as List).length;
    final answers = (result['answers'] as List).length;
    if (questions == 0) throw StateError('No questions extracted');
    return 'Extracted $questions question(s), $answers answer(s)';
  }

  Future<String> _runSearchPipeline(LlmProvider provider) async {
    final store = widget.kbService.store;
    final text = 'We decided to use Riverpod for Flutter state management.';
    final note = await store.addNote(
      text: text,
      tags: ['decision', 'riverpod', 'state-management'],
      author: 'Alice',
      area: 'development',
    );
    final noteId = note.id;
    final search = await widget.kbService.engine.searchByText(
      'Riverpod state management decision',
      matchAll: false,
    );
    final found = search.results.any((r) => r.id == noteId);
    if (!found) throw StateError('Added record was not found by text search');
    return 'Added note $noteId and found it in ${search.results.length} result(s)';
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final notReady = provider == null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flaky, color: AppColors.primaryGlow),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Integration tests',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Model: $_providerLabel',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notReady)
                GlowButton(
                  icon: Icons.play_arrow,
                  onPressed: _runningAll ? null : _runAll,
                  child: Text(_runningAll ? 'Running…' : 'Run all'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (notReady)
            NeoCard(
              gradientColors: [
                AppColors.warning.withValues(alpha: 0.3),
                AppColors.warning.withValues(alpha: 0.05),
              ],
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configure a provider and model in Settings first. '
                      'For Gemma models make sure the model is downloaded.',
                      style: TextStyle(
                        color: AppColors.text.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < _tests.length; index++)
                      _TestCard(
                        test: _tests[index],
                        result: _results[index],
                        runningAll: _runningAll,
                        onRun: () => _runTestAt(index),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestDefinition {
  final String id;
  final String name;
  final String description;
  final Future<String> Function(LlmProvider provider) run;
  final Duration timeout;

  _TestDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.run,
    this.timeout = const Duration(seconds: 60),
  });
}

enum _Status { idle, running, passed, failed }

class _TestResult {
  final String id;
  _Status status;
  String? message;
  Duration? duration;

  _TestResult(this.id)
    : status = _Status.idle,
      message = null,
      duration = null;
}

class _TestCard extends StatelessWidget {
  final _TestDefinition test;
  final _TestResult result;
  final bool runningAll;
  final VoidCallback onRun;

  const _TestCard({
    required this.test,
    required this.result,
    required this.runningAll,
    required this.onRun,
  });

  Color get _statusColor {
    return switch (result.status) {
      _Status.idle => AppColors.textMuted,
      _Status.running => AppColors.warning,
      _Status.passed => AppColors.success,
      _Status.failed => AppColors.error,
    };
  }

  IconData get _statusIcon {
    return switch (result.status) {
      _Status.idle => Icons.circle_outlined,
      _Status.running => Icons.hourglass_top,
      _Status.passed => Icons.check_circle,
      _Status.failed => Icons.error_outline,
    };
  }

  String get _statusLabel {
    return switch (result.status) {
      _Status.idle => 'Idle',
      _Status.running => 'Running',
      _Status.passed => 'Passed',
      _Status.failed => 'Failed',
    };
  }

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_statusIcon, color: _statusColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  test.name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _statusLabel,
                style: TextStyle(
                  color: _statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: ElevatedButton.icon(
                  onPressed: runningAll || result.status == _Status.running
                      ? null
                      : onRun,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Run'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.surfaceHigh,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            test.description,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          if (result.duration != null) ...[
            const SizedBox(height: 8),
            Text(
              'Duration: ${result.duration!.inSeconds}.${(result.duration!.inMilliseconds % 1000).toString().padLeft(3, '0')}s',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          if (result.message != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.message!,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontFamilyFallback: ['Courier'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: result.message!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(60, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
