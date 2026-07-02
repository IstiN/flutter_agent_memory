import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';
import 'add_record_dialog.dart';
import 'record_detail_dialog.dart';

class PeoplePage extends StatefulWidget {
  final KbService kbService;

  const PeoplePage({super.key, required this.kbService});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  Future<Map<String, List<MemoryRecord>>> _load() async {
    final records = await widget.kbService.store.list();
    final groups = <String, List<MemoryRecord>>{};
    for (final r in records) {
      final author = r.author.trim();
      if (author.isEmpty) continue;
      groups.putIfAbsent(author, () => []).add(r);
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
        key: const ValueKey('people-future'),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snapshot.data ?? {};
          if (groups.isEmpty) {
            return _EmptyState();
          }
          final people = groups.keys.toList()
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
                      const Icon(Icons.people_outline, color: AppColors.primaryGlow),
                      const SizedBox(width: 12),
                      const Text(
                        'People',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Chip(
                        label: Text(
                          '${people.length}',
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
                      final person = people[index];
                      final records = groups[person]!;
                      return _PersonCard(
                        person: person,
                        records: records,
                        kbService: widget.kbService,
                      );
                    },
                    childCount: people.length,
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

class _PersonCard extends StatelessWidget {
  final String person;
  final List<MemoryRecord> records;
  final KbService kbService;

  const _PersonCard({required this.person, required this.records, required this.kbService});

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
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  person,
                  style: const TextStyle(
                    color: AppColors.primaryGlow,
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
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 20),
          const Text(
            'No people yet',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Records without an author are grouped here once authors are set.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
