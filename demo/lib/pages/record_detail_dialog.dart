import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';

/// Shows a full detail dialog for a record.
class RecordDetailDialog extends StatelessWidget {
  final MemoryRecord record;
  final KbService kbService;

  const RecordDetailDialog({
    super.key,
    required this.record,
    required this.kbService,
  });

  static Future<void> show(BuildContext context, KbService kbService, String id) async {
    final fresh = await kbService.store.findById(id);
    if (!context.mounted) return;
    if (fresh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Record not found')),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => RecordDetailDialog(record: fresh, kbService: kbService),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      contentPadding: EdgeInsets.zero,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: AppColors.surface,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  TypeBadge(type: record.entityType),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      record.title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle('Content'),
                  SelectionArea(
                    child: Text(
                      record.text,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _InfoRow(icon: Icons.folder_outlined, label: 'Area', value: record.area.isEmpty ? '—' : record.area),
                  _InfoRow(icon: Icons.person_outline, label: 'Author', value: record.author.isEmpty ? '—' : record.author),
                  _InfoRow(icon: Icons.calendar_today_outlined, label: 'Date', value: record.date),
                  _InfoRow(icon: Icons.remove_red_eye_outlined, label: 'Access count', value: '${record.accessCount}'),
                  _InfoRow(icon: Icons.star_outline, label: 'Importance', value: record.importance.toStringAsFixed(2)),
                  if (record.note case final note?) ...[
                    _InfoRow(icon: Icons.category_outlined, label: 'Memory type', value: note.memoryType ?? '—'),
                    _InfoRow(icon: Icons.layers_outlined, label: 'Level', value: _levelName(note.level)),
                    if (note.validFrom?.isNotEmpty == true)
                      _InfoRow(icon: Icons.date_range_outlined, label: 'Valid from', value: note.validFrom!),
                    if (note.validUntil?.isNotEmpty == true)
                      _InfoRow(icon: Icons.event_busy_outlined, label: 'Valid until', value: note.validUntil!),
                  ],
                  const SizedBox(height: 16),
                  _SectionTitle('Tags'),
                  if (record.tags.isEmpty)
                    const Text('No tags', style: TextStyle(color: AppColors.textMuted))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: record.tags
                          .where((t) => !t.startsWith('#source_'))
                          .map((t) => Chip(
                                label: Text(
                                  t.replaceFirst('#', ''),
                                  style: const TextStyle(color: AppColors.text, fontSize: 12),
                                ),
                                backgroundColor: AppColors.surfaceHigh,
                                side: const BorderSide(color: AppColors.border),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  _RelationSection(record: record, kbService: kbService),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _levelName(int level) {
    return switch (level) {
      MemoryLevel.raw => 'raw',
      MemoryLevel.consolidated => 'consolidated',
      MemoryLevel.concept => 'concept',
      _ => 'raw',
    };
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationSection extends StatelessWidget {
  final MemoryRecord record;
  final KbService kbService;

  const _RelationSection({required this.record, required this.kbService});

  void _openRelated(BuildContext context, String targetId) {
    Navigator.of(context).pop();
    RecordDetailDialog.show(context, kbService, targetId);
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    final question = record.question;
    final answeredBy = question?.answeredBy;
    if (answeredBy != null && answeredBy.isNotEmpty) {
      items.add(_relationChip('Answered by', answeredBy, () => _openRelated(context, answeredBy)));
    }

    final answer = record.answer;
    final answersQuestion = answer?.answersQuestion;
    if (answersQuestion != null && answersQuestion.isNotEmpty) {
      items.add(_relationChip('Answers', answersQuestion, () => _openRelated(context, answersQuestion)));
    }

    final note = record.note;
    if (note != null) {
      for (final qid in note.answersQuestions) {
        items.add(_relationChip('Answers', qid, () => _openRelated(context, qid)));
      }
      for (final relation in note.relations) {
        items.add(_relationChip(relation.type, relation.target, () => _openRelated(context, relation.target)));
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Relations'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items,
        ),
      ],
    );
  }

  Widget _relationChip(String label, String targetId, VoidCallback onTap) {
    return ActionChip(
      avatar: const Icon(Icons.link, size: 14, color: AppColors.secondary),
      label: Text(
        '$label $targetId',
        style: const TextStyle(color: AppColors.text, fontSize: 12),
      ),
      backgroundColor: AppColors.surfaceHigh,
      side: const BorderSide(color: AppColors.border),
      onPressed: onTap,
    );
  }
}
