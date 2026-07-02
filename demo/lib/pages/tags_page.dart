import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';
import 'add_record_dialog.dart';
import 'record_detail_dialog.dart';

class TagsPage extends StatefulWidget {
  final KbService kbService;

  const TagsPage({super.key, required this.kbService});

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  Future<Map<String, List<MemoryRecord>>> _load() async {
    final records = await widget.kbService.store.list();
    final groups = <String, List<MemoryRecord>>{};
    for (final r in records) {
      for (var t in r.tags) {
        if (t.startsWith('#source_')) continue;
        t = t.replaceFirst('#', '').trim().toLowerCase();
        if (t.isEmpty) continue;
        groups.putIfAbsent(t, () => []).add(r);
      }
    }
    return groups;
  }

  Future<void> _refresh() async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<Map<String, List<MemoryRecord>>>(
        key: const ValueKey('tags-future'),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snapshot.data ?? {};
          if (groups.isEmpty) {
            return _EmptyState(onAdd: () => _showAddDialog(context));
          }
          final tags = groups.keys.toList()
            ..sort((a, b) {
              final countDiff = groups[b]!.length.compareTo(groups[a]!.length);
              return countDiff != 0 ? countDiff : a.compareTo(b);
            });
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.local_offer_outlined, color: AppColors.secondary),
                      const SizedBox(width: 12),
                      Text(
                        'Tags',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Chip(
                        label: Text(
                          '${tags.length}',
                          style: const TextStyle(color: AppColors.text, fontSize: 12),
                        ),
                        backgroundColor: AppColors.surfaceHigh,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final tag = tags[index];
                      final records = groups[tag]!;
                      return _TagCard(
                        tag: tag,
                        records: records,
                        kbService: widget.kbService,
                      );
                    },
                    childCount: tags.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: GlowButton(
        icon: Icons.add,
        onPressed: () => _showAddDialog(context),
        child: const Text('Add record'),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AddRecordDialog(kbService: widget.kbService),
    );
    if (added == true) _refresh();
  }
}

class _TagCard extends StatelessWidget {
  final String tag;
  final List<MemoryRecord> records;
  final KbService kbService;

  const _TagCard({required this.tag, required this.records, required this.kbService});

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '#$tag',
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Chip(
                label: Text(
                  '${records.length} record${records.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                backgroundColor: AppColors.surfaceHigh,
                side: const BorderSide(color: AppColors.border),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: records
                .take(8)
                .map(
                  (r) => ActionChip(
                    avatar: Icon(
                      TypeBadge.iconFor(r.entityType),
                      size: 14,
                      color: TypeBadge.colorFor(r.entityType),
                    ),
                    label: Text(
                      r.title,
                      style: const TextStyle(color: AppColors.text, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    backgroundColor: AppColors.surfaceHigh,
                    side: const BorderSide(color: AppColors.border),
                    onPressed: () => RecordDetailDialog.show(context, kbService, r.id),
                  ),
                )
                .toList(),
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_offer_outlined,
            size: 64,
            color: AppColors.secondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 20),
          const Text(
            'No tags yet',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add records with tags to see them grouped here.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
