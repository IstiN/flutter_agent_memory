import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';

class SearchPage extends StatefulWidget {
  final KbService kbService;

  const SearchPage({super.key, required this.kbService});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _tagsController = TextEditingController();
  final _textController = TextEditingController();
  bool _loading = false;
  List<KBSearchResult> _results = [];
  List<String> _generatedTags = [];
  String? _error;
  String _mode = 'tags';

  Future<void> _search() async {
    setState(() => _error = null);
    if (_mode == 'tags') {
      await _searchByTags();
    } else {
      await _searchByText();
    }
  }

  Future<void> _searchByTags() async {
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tags.isEmpty) return;
    setState(() => _loading = true);
    try {
      final results = await widget.kbService.engine.searchByTags(tags, matchAll: false);
      setState(() {
        _results = results;
        _generatedTags = [];
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _searchByText() async {
    final query = _textController.text.trim();
    if (query.isEmpty) return;
    if (widget.kbService.providerService.provider == null) {
      setState(
        () => _error = 'Configure provider in Settings to use text search.',
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await widget.kbService.engine.searchByText(query, matchAll: false);
      setState(() {
        _results = result.results;
        _generatedTags = result.generatedTags;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchModeToggle(
            mode: _mode,
            onChanged: (m) => setState(() {
              _mode = m;
              _results = [];
              _generatedTags = [];
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.35),
                  AppColors.secondary.withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(1),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Semantics(
                label: _mode == 'tags' ? 'Search by tags' : 'Search by text',
                child: TextField(
                  controller: _mode == 'tags' ? _tagsController : _textController,
                  style: const TextStyle(color: AppColors.text, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: _mode == 'tags'
                        ? 'Enter tags separated by commas...'
                        : 'Describe what you are looking for...',
                    hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.7)),
                    prefixIcon: const Icon(Icons.search, color: AppColors.primaryGlow),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward, color: AppColors.primaryGlow),
                            onPressed: _search,
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: NeoCard(
                padding: const EdgeInsets.all(14),
                gradientColors: [
                  AppColors.error.withValues(alpha: 0.4),
                  AppColors.error.withValues(alpha: 0.1),
                ],
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_generatedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Text(
                    'Generated tags:',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  ..._generatedTags.map(
                    (t) => Chip(
                      label: Text(t, style: const TextStyle(color: AppColors.text)),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _results.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search,
                          size: 56,
                          color: AppColors.textMuted.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No results yet',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return Semantics(
                        label: r.title ?? 'Search result',
                        child: NeoCard(
                          onTap: () => widget.kbService.store.recordAccess(r.id!),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                TypeBadge(type: r.entityType),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.touch_app,
                                    color: AppColors.textMuted,
                                    size: 20,
                                  ),
                                  tooltip: 'Record access',
                                  onPressed: () => widget.kbService.store.recordAccess(r.id!),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              r.title ?? 'Untitled',
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (r.matchedTags.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: r.matchedTags
                                    .map(
                                      (t) => Chip(
                                        label: Text(
                                          t,
                                          style: const TextStyle(
                                            color: AppColors.secondaryGlow,
                                            fontSize: 12,
                                          ),
                                        ),
                                        backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                                        side: BorderSide(
                                          color: AppColors.secondary.withValues(alpha: 0.4),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _SearchModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'tags', label: Text('By tags')),
        ButtonSegment(value: 'text', label: Text('By text')),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
