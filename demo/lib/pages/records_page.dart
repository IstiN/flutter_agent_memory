import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';

class RecordsPage extends StatefulWidget {
  final KbService kbService;

  const RecordsPage({super.key, required this.kbService});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  Future<List<MemoryRecord>> _load() => widget.kbService.store.list();

  Future<void> _refresh() async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primaryGlow,
        backgroundColor: AppColors.surface,
        onRefresh: _refresh,
        child: FutureBuilder<List<MemoryRecord>>(
          future: _load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return _EmptyState(onAdd: _showAddDialog);
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final r = records[index];
                return Semantics(
                  label: r.title,
                  child: _RecordTile(
                    record: r,
                    onDelete: () async {
                      await widget.kbService.store.deleteRecord(r.id);
                      _refresh();
                    },
                    onPromote: r.note != null
                        ? () async {
                            final next = r.note!.level + 1;
                            if (next > MemoryLevel.concept) return;
                            await widget.kbService.store.promote(r.id, next);
                            _refresh();
                          }
                        : null,
                    onRelate: () async {
                      final target = await _pickTarget(context, r.id);
                      if (target != null) {
                        await widget.kbService.store.addRelation(
                          r.id,
                          target,
                          'relatedTo',
                        );
                        _refresh();
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: GlowButton(
        icon: Icons.add,
        onPressed: _showAddDialog,
        child: const Text('Add record'),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AddRecordDialog(kbService: widget.kbService),
    );
    if (added == true) _refresh();
  }

  Future<String?> _pickTarget(BuildContext context, String excludeId) async {
    final records = await widget.kbService.store.list();
    if (!context.mounted) return null;
    final choices = records.where((r) => r.id != excludeId).toList();
    if (choices.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Select target record',
          style: TextStyle(color: AppColors.text),
        ),
        children: choices
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, r.id),
                child: Row(
                  children: [
                    TypeBadge(type: r.entityType),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.title,
                        style: const TextStyle(color: AppColors.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Empty state',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Icon(
            Icons.auto_stories,
            size: 64,
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your knowledge base is empty',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add questions, answers and notes to build a memory graph.',
            style: TextStyle(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GlowButton(icon: Icons.add, onPressed: onAdd, child: const Text('Add first record')),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final MemoryRecord record;
  final VoidCallback onDelete;
  final VoidCallback? onPromote;
  final VoidCallback onRelate;

  const _RecordTile({
    required this.record,
    required this.onDelete,
    this.onPromote,
    required this.onRelate,
  });

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TypeBadge(type: record.entityType),
              const SizedBox(width: 10),
              if (record.area.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    record.area,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
              const Spacer(),
              _ActionMenu(
                onDelete: onDelete,
                onPromote: onPromote,
                onRelate: onRelate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            record.title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (record.text != record.title) ...[
            const SizedBox(height: 8),
            Text(
              record.text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: record.tags
                .where((t) => !t.startsWith('#source_'))
                .map(
                  (t) => Chip(
                    label: Text(
                      t.replaceFirst('#', ''),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    backgroundColor: AppColors.surfaceHigh,
                    side: const BorderSide(color: AppColors.border),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          _RelationRow(record: record),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, size: 14, color: AppColors.textMuted.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                '${record.accessCount}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Icon(Icons.star_outline, size: 14, color: AppColors.textMuted.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                record.importance.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RelationRow extends StatelessWidget {
  final MemoryRecord record;

  const _RelationRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    void add(String label, String targetId) {
      items.add(
        ActionChip(
          avatar: const Icon(Icons.link, size: 14, color: AppColors.secondary),
          label: Text(
            '$label $targetId',
            style: const TextStyle(color: AppColors.text, fontSize: 12),
          ),
          backgroundColor: AppColors.surfaceHigh,
          side: const BorderSide(color: AppColors.border),
          visualDensity: VisualDensity.compact,
          onPressed: () {},
        ),
      );
    }

    final question = record.question;
    final answeredBy = question?.answeredBy;
    if (answeredBy != null && answeredBy.isNotEmpty) {
      add('Answered by', answeredBy);
    }

    final answer = record.answer;
    final answersQuestion = answer?.answersQuestion;
    if (answersQuestion != null && answersQuestion.isNotEmpty) {
      add('Answers', answersQuestion);
    }

    final note = record.note;
    if (note != null) {
      for (final qid in note.answersQuestions) {
        add('Answers', qid);
      }
      for (final relation in note.relations) {
        add(relation.type, relation.target);
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items,
    );
  }
}

class _ActionMenu extends StatelessWidget {
  final VoidCallback onDelete;
  final VoidCallback? onPromote;
  final VoidCallback onRelate;

  const _ActionMenu({
    required this.onDelete,
    this.onPromote,
    required this.onRelate,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        if (value == 'delete') onDelete();
        if (value == 'promote') onPromote?.call();
        if (value == 'relate') onRelate();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'relate',
          child: Row(
            children: [
              Icon(Icons.link, color: AppColors.secondary, size: 18),
              SizedBox(width: 10),
              Text('Add relation', style: TextStyle(color: AppColors.text)),
            ],
          ),
        ),
        if (onPromote != null)
          PopupMenuItem(
            value: 'promote',
            child: Row(
              children: [
                const Icon(Icons.trending_up, color: AppColors.success, size: 18),
                const SizedBox(width: 10),
                Text('Promote', style: TextStyle(color: AppColors.text)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: AppColors.error, size: 18),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: AppColors.text)),
            ],
          ),
        ),
      ],
    );
  }
}

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

            // Create questions first so answers can be linked by temp id.
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
