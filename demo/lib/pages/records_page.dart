import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';

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
        onRefresh: _refresh,
        child: FutureBuilder<List<MemoryRecord>>(
          future: _load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return const Center(
                child: Text('No records yet. Tap + to add one.'),
              );
            }
            return ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final r = records[index];
                return _RecordTile(
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
                  kbService: widget.kbService,
                  onChanged: _refresh,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await showDialog<bool>(
            context: context,
            builder: (context) => AddRecordDialog(kbService: widget.kbService),
          );
          if (added == true) _refresh();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final MemoryRecord record;
  final VoidCallback onDelete;
  final VoidCallback? onPromote;
  final KbService kbService;
  final VoidCallback onChanged;

  const _RecordTile({
    required this.record,
    required this.onDelete,
    this.onPromote,
    required this.kbService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      record.entityType,
      'area: ${record.area}',
      if (record.accessCount > 0) 'views: ${record.accessCount}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text(record.title),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'delete') onDelete();
            if (value == 'promote') onPromote?.call();
            if (value == 'relate') {
              final store = kbService.store;
              final target = await _pickTarget(context, record.id);
              if (target != null) {
                await store.addRelation(record.id, target, 'relatedTo');
                onChanged();
              }
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'relate', child: Text('Add relation')),
            if (onPromote != null)
              PopupMenuItem(value: 'promote', child: Text('Promote to ${_nextLevelName()}')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.text),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: record.tags
                      .map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _nextLevelName() {
    final next = record.note!.level + 1;
    return switch (next) {
      MemoryLevel.consolidated => 'consolidated',
      MemoryLevel.concept => 'concept',
      _ => 'level $next',
    };
  }

  Future<String?> _pickTarget(BuildContext context, String excludeId) async {
    final records = await kbService.store.list();
    if (!context.mounted) return null;
    final choices = records.where((r) => r.id != excludeId).toList();
    if (choices.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select target record'),
        children: choices
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, r.id),
                child: Text('${r.entityType}: ${r.title}'),
              ),
            )
            .toList(),
      ),
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
  final _areaController = TextEditingController(text: 'general');
  final _tagsController = TextEditingController();
  final _linkController = TextEditingController();
  String _memoryType = 'observation';
  int _level = MemoryLevel.raw;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add record'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'question', label: Text('Question')),
                ButtonSegment(value: 'answer', label: Text('Answer')),
                ButtonSegment(value: 'note', label: Text('Note')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(labelText: 'Text'),
              maxLines: 4,
            ),
            TextField(
              controller: _areaController,
              decoration: const InputDecoration(labelText: 'Area'),
            ),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma separated)',
              ),
            ),
            if (_type == 'answer')
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  labelText: 'Answers question id (e.g. q_0001)',
                ),
              ),
            if (_type == 'note') ...[
              DropdownButtonFormField<String>(
                initialValue: _memoryType,
                decoration: const InputDecoration(labelText: 'Memory type'),
                items: const [
                  DropdownMenuItem(value: 'fact', child: Text('fact')),
                  DropdownMenuItem(value: 'event', child: Text('event')),
                  DropdownMenuItem(value: 'observation', child: Text('observation')),
                  DropdownMenuItem(value: 'decision', child: Text('decision')),
                  DropdownMenuItem(value: 'belief', child: Text('belief')),
                ],
                onChanged: (v) => setState(() => _memoryType = v!),
              ),
              DropdownButtonFormField<int>(
                initialValue: _level,
                decoration: const InputDecoration(labelText: 'Level'),
                items: const [
                  DropdownMenuItem(value: MemoryLevel.raw, child: Text('raw')),
                  DropdownMenuItem(value: MemoryLevel.consolidated, child: Text('consolidated')),
                  DropdownMenuItem(value: MemoryLevel.concept, child: Text('concept')),
                ],
                onChanged: (v) => setState(() => _level = v!),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final text = _textController.text.trim();
            if (text.isEmpty) return;
            final tags = _tagsController.text
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList();
            final area = _areaController.text.trim();
            final store = widget.kbService.store;
            final navigator = Navigator.of(context);
            switch (_type) {
              case 'question':
                await store.addQuestion(text: text, area: area, tags: tags);
              case 'answer':
                await store.addAnswer(
                  text: text,
                  area: area,
                  tags: tags,
                  answersQuestion: _linkController.text.trim().isEmpty
                      ? null
                      : _linkController.text.trim(),
                );
              case 'note':
                await store.addNote(
                  text: text,
                  area: area,
                  tags: tags,
                  memoryType: _memoryType,
                  level: _level,
                );
            }
            navigator.pop(true);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
