import 'package:flutter/material.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';

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
        _error = null;
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
      setState(() => _error = 'Configure provider in Settings to use text search.');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await widget.kbService.engine.searchByText(query, matchAll: false);
      setState(() {
        _results = result.results;
        _generatedTags = result.generatedTags;
        _error = null;
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: 'Tags (comma separated)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchByTags,
              ),
            ),
            onSubmitted: (_) => _searchByTags(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: 'Natural language query',
              helperText: 'Requires a configured LLM provider',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchByText,
              ),
            ),
            onSubmitted: (_) => _searchByText(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_generatedTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Generated tags: ${_generatedTags.join(', ')}'),
            ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('No results'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return ListTile(
                        title: Text(r.title ?? r.id ?? ''),
                        subtitle: Text('${r.entityType} · matched: ${r.matchedTags.join(', ')}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.touch_app),
                          tooltip: 'Record access',
                          onPressed: () => widget.kbService.store.recordAccess(r.id!),
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
