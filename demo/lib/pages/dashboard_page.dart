import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';
import '../utils/mermaid_prettifier.dart';
import '../widgets/mermaid_diagram_view.dart';
import 'add_record_dialog.dart';
import 'people_page.dart';
import 'record_detail_dialog.dart';
import 'records_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'tags_page.dart';

/// Desktop-style dashboard with a left sidebar, top search bar, and a
/// two-pane Records + Graph body by default. Sidebar items switch to
/// dedicated full-page views for Search, Records, Graph, Tags, People,
/// and Settings.
class DashboardPage extends StatefulWidget {
  final KbService kbService;

  const DashboardPage({super.key, required this.kbService});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 1; // Graph selected by default to match reference.
  String _query = '';
  int _recordsTab = 0; // 0 = Records, 1 = Graph
  int _graphVersion = 0;

  static const _destinations = [
    _NavItem(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Search'),
    _NavItem(icon: Icons.account_tree_outlined, selectedIcon: Icons.account_tree, label: 'Graph'),
    _NavItem(icon: Icons.library_books_outlined, selectedIcon: Icons.library_books, label: 'Records'),
    _NavItem(icon: Icons.local_offer_outlined, selectedIcon: Icons.local_offer, label: 'Tags'),
    _NavItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'People'),
    _NavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
  ];

  Future<void> _showAddDialog(BuildContext context) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AddRecordDialog(kbService: widget.kbService),
    );
    if (added == true && mounted) setState(() {});
  }

  Future<void> _generateSamples() async {
    // Add in reverse display order so the newest record appears at the top
    // of the list after generation.
    final samples = [
      _Sample(type: 'note', text: 'meeting.vtt', tags: ['source', 'transcript'], author: 'Alice', area: 'development'),
      _Sample(type: 'note', text: 'Scalability & maintainability', tags: ['architecture', 'backend'], author: 'Bob', area: 'development'),
      _Sample(type: 'answer', text: 'We decided on Riverpod', tags: ['decision', 'architecture', 'state-management'], author: 'Alice', area: 'development'),
      _Sample(type: 'question', text: 'Why Riverpod over Provider?', tags: ['flutter', 'state-management', 'decision'], author: 'Bob', area: 'development'),
      _Sample(type: 'question', text: 'How do we handle offline sync?', tags: ['flutter', 'backend', 'architecture'], author: 'Charlie', area: 'development'),
      _Sample(type: 'answer', text: 'Use a local SQLite cache with sync queue', tags: ['decision', 'backend', 'flutter'], author: 'Diana', area: 'development'),
      _Sample(type: 'question', text: 'What is our AI integration strategy?', tags: ['ai', 'roadmap'], author: 'Diana', area: 'research'),
      _Sample(type: 'note', text: 'User interview findings', tags: ['ux', 'design', 'research'], author: 'Charlie', area: 'design'),
    ];

    for (final s in samples) {
      switch (s.type) {
        case 'question':
          await widget.kbService.store.addQuestion(text: s.text, tags: s.tags, author: s.author, area: s.area);
        case 'answer':
          await widget.kbService.store.addAnswer(text: s.text, tags: s.tags, author: s.author, area: s.area);
        case 'note':
        default:
          await widget.kbService.store.addNote(text: s.text, tags: s.tags, author: s.author, area: s.area);
      }
      // Stagger timestamps so the list order stays predictable.
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await widget.kbService.graphBuilder.build(maxMermaidNodes: 40);

    if (!mounted) return;
    setState(() => _graphVersion++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sample records generated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDashboard = _selectedIndex == 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: isDashboard
          ? FloatingActionButton.extended(
              onPressed: () => _showAddDialog(context),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add record'),
            )
          : null,
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            onGenerateSamples: _generateSamples,
            storage: widget.kbService.storage,
          ),
          Expanded(
            child: isDashboard ? _buildDashboardBody() : _buildPage(_selectedIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody() {
    return Column(
      children: [
        _SearchBar(
          query: _query,
          onQueryChanged: (v) => setState(() => _query = v),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TabBar(
                      selectedIndex: _recordsTab,
                      onSelected: (i) => setState(() => _recordsTab = i),
                    ),
                    Expanded(
                      child: _recordsTab == 0
                          ? _RecordsPanel(
                              kbService: widget.kbService,
                              query: _query,
                            )
                          : _GraphPanel(
                              key: ValueKey('left-$_graphVersion'),
                              kbService: widget.kbService,
                            ),
                    ),
                  ],
                ),
              ),
              if (_recordsTab == 0)
                Expanded(
                  flex: 45,
                  child: _GraphPanel(
                    key: ValueKey('right-$_graphVersion'),
                    kbService: widget.kbService,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPage(int index) {
    return switch (index) {
      0 => SearchPage(kbService: widget.kbService),
      2 => RecordsPage(kbService: widget.kbService),
      3 => TagsPage(kbService: widget.kbService),
      4 => PeoplePage(kbService: widget.kbService),
      5 => SettingsPage(kbService: widget.kbService),
      _ => _buildDashboardBody(),
    };
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback? onGenerateSamples;
  final KbStorage storage;

  const _Sidebar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.onGenerateSamples,
    required this.storage,
  });

  Future<int> _count() async {
    final q = await storage.listEntityIds('question');
    final a = await storage.listEntityIds('answer');
    final n = await storage.listEntityIds('note');
    return q.length + a.length + n.length;
  }

  @override
  Widget build(BuildContext context) {
    const items = _DashboardPageState._destinations;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                  ),
                  child: const Icon(Icons.memory, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Flutter Agent\nMemory',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = selectedIndex == index;
                return _SidebarTile(
                  icon: selected ? item.selectedIcon : item.icon,
                  label: item.label,
                  selected: selected,
                  onTap: () => onDestinationSelected(index),
                );
              },
            ),
          ),
          if (onGenerateSamples != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onGenerateSamples,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Generate sample data'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    backgroundColor: AppColors.surfaceHigh.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.storage_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Text(
                  'Indexed',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                FutureBuilder<int>(
                  future: _count(),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    return Text(
                      '$count records',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected ? AppColors.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: AppColors.border.withValues(alpha: 0.6))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primaryGlow : AppColors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.text : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;

  const _SearchBar({required this.query, required this.onQueryChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
      ),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        ),
        child: TextField(
          onChanged: onQueryChanged,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Search by text or tags...',
            hintStyle: TextStyle(color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textMuted),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _TabBar({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          _Tab(
            label: 'Records',
            selected: selectedIndex == 0,
            onTap: () => onSelected(0),
          ),
          const SizedBox(width: 8),
          _Tab(
            label: 'Graph',
            selected: selectedIndex == 1,
            onTap: () => onSelected(1),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$label tab',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.secondaryGlow : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.text : AppColors.textMuted,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordsPanel extends StatefulWidget {
  final KbService kbService;
  final String query;

  const _RecordsPanel({required this.kbService, required this.query});

  @override
  State<_RecordsPanel> createState() => _RecordsPanelState();
}

class _RecordsPanelState extends State<_RecordsPanel> {
  Future<List<MemoryRecord>> _load() async {
    final records = await widget.kbService.store.list();
    final q = widget.query.trim().toLowerCase();
    if (q.isEmpty) return records;
    return records.where((r) {
      return r.title.toLowerCase().contains(q) ||
          r.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: FutureBuilder<List<MemoryRecord>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return Center(
              child: Semantics(
                label: 'Empty state',
                child: Text(
                  widget.query.isEmpty ? 'No records yet' : 'No matches',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 100, left: 20, right: 20, top: 8),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final r = records[index];
              return _RecordRow(record: r, kbService: widget.kbService);
            },
          );
        },
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final MemoryRecord record;
  final KbService kbService;

  const _RecordRow({required this.record, required this.kbService});

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static final _tagColorMap = <String, Color>{
    'flutter': AppColors.blue,
    'state-management': AppColors.secondary,
    'decision': AppColors.primary,
    'architecture': AppColors.teal,
    'performance': AppColors.accent,
    'meeting': AppColors.blue,
    'transcript': AppColors.secondary,
    'source': AppColors.textMuted,
  };

  static final _hiddenTags = <String>{
    'question',
    'answer',
    'note',
    'q',
    'a',
    'n',
  };

  Color _tagColor(String tag) {
    final key = tag.replaceFirst('#', '').toLowerCase();
    return _tagColorMap[key] ?? AppColors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final date = _parseDate(record.date);
    final tags = record.tags
        .map((t) => t.trim())
        .where((t) {
          if (t.isEmpty) return false;
          final normalized = t.replaceFirst('#', '').toLowerCase();
          return !_hiddenTags.contains(normalized) &&
              !normalized.startsWith('source_');
        })
        .toList();

    return GestureDetector(
      onTap: () => RecordDetailDialog.show(context, kbService, record.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: tags.map((t) {
                    final color = _tagColor(t);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        t.replaceFirst('#', ''),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _formatDate(date),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    ),);
  }

  DateTime _parseDate(String raw) {
    if (raw.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return DateTime.now();
    }
  }

  String _formatDate(DateTime d) {
    final m = _monthNames[d.month - 1];
    return '$m ${d.day}, ${d.year}';
  }
}

class _GraphPanel extends StatefulWidget {
  final KbService kbService;

  const _GraphPanel({super.key, required this.kbService});

  @override
  State<_GraphPanel> createState() => _GraphPanelState();
}

class _GraphPanelState extends State<_GraphPanel> {
  String? _mermaid;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _buildGraph();
  }

  Future<void> _buildGraph() async {
    try {
      await widget.kbService.graphBuilder.build(maxMermaidNodes: 40);
      final md = await widget.kbService.storage.readFile('GRAPH.md');
      if (md == null) {
        setState(() {
          _error = 'GRAPH.md was not generated.';
          _loading = false;
        });
        return;
      }
      final raw = _extractMermaid(md);
      setState(() {
        _mermaid = raw == null ? null : prettifyMermaid(raw);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String? _extractMermaid(String markdown) {
    final match = RegExp(
      r'```mermaid\n([\s\S]*?)\n```',
      multiLine: true,
    ).firstMatch(markdown);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.text, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_mermaid == null || _mermaid!.trim().isEmpty) {
      return const Center(
        child: Text(
          'No graph yet.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return MermaidDiagramView(
      diagram: _mermaid!,
      onNodeTap: (mermaidId) {
        final recordId = recordIdFromMermaidNode(mermaidId);
        if (recordId == null) return;
        RecordDetailDialog.show(context, widget.kbService, recordId);
      },
    );
  }
}

class _Sample {
  final String type;
  final String text;
  final List<String> tags;
  final String author;
  final String area;

  const _Sample({
    required this.type,
    required this.text,
    required this.tags,
    this.author = 'agent',
    this.area = 'general',
  });
}

