import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';

class AddRecordDialog extends StatefulWidget {
  final KbService kbService;

  const AddRecordDialog({super.key, required this.kbService});

  @override
  State<AddRecordDialog> createState() => _AddRecordDialogState();
}

class _AddRecordDialogState extends State<AddRecordDialog> {
  String _type = 'question';
  final _textController = TextEditingController();
  final _rawTextController = TextEditingController();
  final _areaController = TextEditingController(text: 'general');
  final _tagsController = TextEditingController();
  final _linkController = TextEditingController();
  String _memoryType = 'observation';
  int _level = MemoryLevel.raw;

  String? _imageDataUrl;
  bool _analyzing = false;
  String? _errorMessage;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _errorMessage = 'Could not read image bytes');
      return;
    }
    final mime = file.extension != null ? 'image/${file.extension}' : 'image/png';
    final b64 = base64Encode(bytes);
    setState(() {
      _imageDataUrl = 'data:$mime;base64,$b64';
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Add record', style: TextStyle(color: AppColors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'question', label: Text('Question')),
                ButtonSegment(value: 'answer', label: Text('Answer')),
                ButtonSegment(value: 'note', label: Text('Note')),
                ButtonSegment(value: 'image', label: Text('Image')),
                ButtonSegment(value: 'raw', label: Text('Raw text')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            if (_type == 'raw') ...[
              TextField(
                controller: _rawTextController,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: 'Paste raw text here',
                  hintText: 'Any text dump; LLM will extract title, summary and tags.',
                ),
                maxLines: 8,
              ),
              const SizedBox(height: 12),
              if (!widget.kbService.rawTextProcessor.available)
                const Text(
                  'Configure an LLM provider in Settings to auto-process raw text.',
                  style: TextStyle(color: AppColors.warning),
                ),
            ] else if (_type == 'image') ...[
              if (_imageDataUrl == null)
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image, color: AppColors.text),
                  label: const Text('Pick image', style: TextStyle(color: AppColors.text)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _imageDataUrl!,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _imageDataUrl = null;
                      }),
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      label: const Text('Remove', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
                ),
              if (!widget.kbService.imageAnalysis.available)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Configure an LLM provider in Settings to analyze images.',
                    style: TextStyle(color: AppColors.warning),
                  ),
                ),
              const SizedBox(height: 12),
            ] else ...[
              TextField(
                controller: _textController,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Text'),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _areaController,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(labelText: 'Area'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
              ),
            ),
            if (_type == 'answer')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: _linkController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: 'Answers question id (e.g. q_0001)',
                  ),
                ),
              ),
            if (_type == 'note') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _memoryType,
                dropdownColor: AppColors.surfaceHigh,
                decoration: const InputDecoration(labelText: 'Memory type'),
                items: const [
                  DropdownMenuItem(value: 'fact', child: Text('fact')),
                  DropdownMenuItem(value: 'event', child: Text('event')),
                  DropdownMenuItem(value: 'observation', child: Text('observation')),
                  DropdownMenuItem(value: 'decision', child: Text('decision')),
                  DropdownMenuItem(value: 'belief', child: Text('belief')),
                ],
                onChanged: (v) => setState(() => _memoryType = v!),
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _level,
                dropdownColor: AppColors.surfaceHigh,
                decoration: const InputDecoration(labelText: 'Level'),
                items: const [
                  DropdownMenuItem(value: MemoryLevel.raw, child: Text('raw')),
                  DropdownMenuItem(
                    value: MemoryLevel.consolidated,
                    child: Text('consolidated'),
                  ),
                  DropdownMenuItem(value: MemoryLevel.concept, child: Text('concept')),
                ],
                onChanged: (v) => setState(() => _level = v!),
                style: const TextStyle(color: AppColors.text),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        GlowButton(
          onPressed: _analyzing ? null : _submit,
          child: _analyzing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    final store = widget.kbService.store;
    final area = _areaController.text.trim();
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    switch (_type) {
      case 'question':
        final text = _textController.text.trim();
        if (text.isEmpty) return;
        await store.addQuestion(text: text, area: area, tags: tags);
      case 'answer':
        final text = _textController.text.trim();
        if (text.isEmpty) return;
        await store.addAnswer(
          text: text,
          area: area,
          tags: tags,
          answersQuestion: _linkController.text.trim().isEmpty
              ? null
              : _linkController.text.trim(),
        );
      case 'note':
        final text = _textController.text.trim();
        if (text.isEmpty) return;
        await store.addNote(
          text: text,
          area: area,
          tags: tags,
          memoryType: _memoryType,
          level: _level,
        );
      case 'image':
        final dataUrl = _imageDataUrl;
        if (dataUrl == null) return;
        setState(() => _analyzing = true);
        try {
          String text;
          List<String> imageTags;
          if (widget.kbService.imageAnalysis.available) {
            final result = await widget.kbService.imageAnalysis.analyze(dataUrl);
            text = 'Image analysis:\n${result['description']}';
            imageTags = (result['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
          } else {
            text = 'Image note';
            imageTags = [];
          }
          final allTags = <String>{...tags, ...imageTags}.toList();
          await store.addNote(
            text: '$text\n\n![image]($dataUrl)',
            area: area.isEmpty ? 'images' : area,
            tags: allTags,
            memoryType: 'observation',
            level: MemoryLevel.raw,
          );
        } catch (e) {
          setState(() {
            _analyzing = false;
            _errorMessage = e.toString();
          });
          return;
        }
        setState(() => _analyzing = false);
      case 'raw':
        final raw = _rawTextController.text.trim();
        if (raw.isEmpty) return;
        setState(() => _analyzing = true);
        try {
          if (widget.kbService.rawTextProcessor.available) {
            final result = await widget.kbService.rawTextProcessor.process(raw);
            final globalArea = (result['area'] as String).isEmpty
                ? area
                : result['area'] as String;

            String itemArea(dynamic item) {
              final a = (item['area'] as String? ?? '').trim();
              return a.isEmpty ? globalArea : a;
            }

            List<String> itemTags(dynamic item) {
              final itemTopics = (item['topics'] as List? ?? [])
                  .map((e) => e.toString())
                  .where((t) => t.isNotEmpty);
              final itemTags = (item['tags'] as List? ?? [])
                  .map((e) => e.toString())
                  .where((t) => t.isNotEmpty);
              return <String>{
                ...tags,
                ...itemTopics,
                ...itemTags,
              }.toList();
            }

            final questionIds = <String, String>{};
            final questionEntries = result['questions'] as List? ?? [];
            for (final q in questionEntries) {
              final record = await store.addQuestion(
                text: q['text'] as String,
                author: (q['author'] as String? ?? '').isEmpty
                    ? 'agent'
                    : q['author'] as String,
                area: itemArea(q),
                tags: itemTags(q),
              );
              questionIds[q['id'] as String] = record.id;
            }

            final answerEntries = result['answers'] as List? ?? [];
            for (final a in answerEntries) {
              final questionTempId = a['answersQuestion'] as String?;
              await store.addAnswer(
                text: a['text'] as String,
                author: (a['author'] as String? ?? '').isEmpty
                    ? 'agent'
                    : a['author'] as String,
                area: itemArea(a),
                tags: itemTags(a),
                answersQuestion: questionIds[questionTempId],
                quality: (a['quality'] as num?)?.toDouble() ?? 0.8,
              );
            }

            final noteEntries = result['notes'] as List? ?? [];
            for (final n in noteEntries) {
              final links = (n['links'] as List? ?? [])
                  .whereType<Map<String, dynamic>>()
                  .map((l) => '[${l['title']}](${l['url']})')
                  .join('\n');
              var noteText = (n['text'] as String? ?? '').trim();
              if (links.isNotEmpty) {
                noteText = '$noteText\n\n$links';
              }
              await store.addNote(
                text: noteText,
                author: (n['author'] as String? ?? '').isEmpty
                    ? 'agent'
                    : n['author'] as String,
                area: itemArea(n),
                tags: itemTags(n),
                memoryType: 'observation',
                level: MemoryLevel.raw,
              );
            }
          } else {
            await store.addNote(
              text: raw,
              area: area,
              tags: tags,
              memoryType: 'observation',
              level: MemoryLevel.raw,
            );
          }
        } catch (e) {
          setState(() {
            _analyzing = false;
            _errorMessage = e.toString();
          });
          return;
        }
        setState(() => _analyzing = false);
    }
    navigator.pop(true);
  }
}
