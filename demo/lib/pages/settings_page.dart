import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/link.dart';

import '../services/kb_service.dart';
import '../services/provider_service.dart';

class SettingsPage extends StatefulWidget {
  final KbService kbService;

  const SettingsPage({super.key, required this.kbService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _tokenController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  late ProviderType _type;
  bool _saving = false;
  String? _message;
  int _recordCount = 0;

  @override
  void initState() {
    super.initState();
    final settings = widget.kbService.settings;
    _type = ProviderType.fromString(settings.provider);
    _tokenController.text = settings.apiKey;
    _baseUrlController.text = settings.baseUrl;
    _modelController.text = settings.model;
    _loadRecordCount();
  }

  Future<void> _loadRecordCount() async {
    final storage = widget.kbService.storage;
    final q = await storage.listEntityIds('question');
    final a = await storage.listEntityIds('answer');
    final n = await storage.listEntityIds('note');
    setState(() => _recordCount = q.length + a.length + n.length);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.kbService.settings;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Provider', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SegmentedButton<ProviderType>(
            segments: const [
              ButtonSegment(value: ProviderType.ollama, label: Text('Ollama')),
              ButtonSegment(value: ProviderType.openRouter, label: Text('OpenRouter')),
              ButtonSegment(value: ProviderType.openAi, label: Text('OpenAI')),
              ButtonSegment(value: ProviderType.none, label: Text('None')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          if (_type == ProviderType.ollama) ...[
            const SizedBox(height: 12),
            Link(
              uri: Uri.parse('https://github.com/ollama/ollama'),
              builder: (context, followLink) => TextButton(
                onPressed: followLink,
                child: const Text('Get Ollama'),
              ),
            ),
          ],
          if (_type == ProviderType.openRouter) ...[
            const SizedBox(height: 12),
            Link(
              uri: Uri.parse('https://openrouter.ai/keys'),
              builder: (context, followLink) => TextButton(
                onPressed: followLink,
                child: const Text('Get OpenRouter key'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            decoration: InputDecoration(
              labelText: _tokenLabel(),
              helperText: 'Stored only in browser localStorage',
              suffixIcon: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _tokenController.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL (optional)',
              helperText: 'For Ollama e.g. http://localhost:11434',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Model',
              helperText: 'e.g. gpt-4o-mini, llama3, mistral',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save settings'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _reset,
                child: const Text('Reset KB'),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_message!),
            ),
          const SizedBox(height: 24),
          Text('Current settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Provider: ${settings.provider}'),
          Text('Model: ${settings.model.isEmpty ? "—" : settings.model}'),
          Text('Base URL: ${settings.baseUrl.isEmpty ? "—" : settings.baseUrl}'),
          Text('Token saved: ${settings.apiKey.isEmpty ? "no" : "yes"}'),
          Text('Records: $_recordCount'),
        ],
      ),
    );
  }

  String _tokenLabel() {
    return switch (_type) {
      ProviderType.ollama => 'Ollama origin/auth (if required)',
      ProviderType.openRouter => 'OpenRouter API key',
      ProviderType.openAi => 'OpenAI API key',
      ProviderType.none => 'Token (unused)',
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.kbService.updateSettings(
        provider: _type.settingsValue,
        apiKey: _tokenController.text.trim(),
        model: _modelController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
      );
      await _loadRecordCount();
      setState(() => _message = 'Saved. Provider rebuilt.');
    } catch (e) {
      setState(() => _message = 'Error: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset knowledge base?'),
        content: const Text('This deletes all records, answers and notes from browser storage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.kbService.clearAll();
    await _loadRecordCount();
    setState(() => _message = 'Knowledge base reset.');
  }
}
