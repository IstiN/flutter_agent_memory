import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/link.dart';



import '../services/gemma_model_presets.dart';
import '../services/gemma_service.dart';
import '../services/kb_service.dart';
import '../services/provider_service.dart';
import '../services/version_info.dart';
import '../theme/app_theme.dart';

import '../webllm/webllm_service.dart';

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
  late int _webLlmContextWindowSize;
  late int _webLlmMaxOutputTokens;
  bool _saving = false;
  String? _message;
  int _recordCount = 0;
  DemoVersionInfo? _versionInfo;

  @override
  void initState() {
    super.initState();
    final settings = widget.kbService.settings;
    _type = ProviderType.fromString(settings.provider);
    _tokenController.text = settings.apiKey;
    _baseUrlController.text = settings.baseUrl;
    _modelController.text = settings.model;
    _webLlmContextWindowSize = settings.webLlmContextWindowSize;
    _webLlmMaxOutputTokens = settings.webLlmMaxOutputTokens;
    _loadRecordCount();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    final info = await DemoVersionInfo.load();
    if (mounted) setState(() => _versionInfo = info);
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
    final configured = widget.kbService.providerService.provider != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LLM Provider',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _ProviderGrid(
                  selected: _type,
                  onSelected: (t) => setState(() {
                    _type = t;
                    if (t == ProviderType.webllm && _modelController.text.isEmpty) {
                      _modelController.text = webLlmModelPresets.first.id;
                    }
                  }),
                ),
                const SizedBox(height: 16),
                _ProviderHint(type: _type),
              ],
            ),
          ),
          NeoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Credentials',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: _tokenLabel(),
                    helperText: 'Stored only in browser localStorage',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.textMuted),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _tokenController.text),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                    ),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                if (_type != ProviderType.gemma && _type != ProviderType.webllm) ...[
                  TextField(
                    controller: _baseUrlController,
                    style: const TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Base URL (optional)',
                      helperText: _type == ProviderType.local
                          ? 'Full URL, e.g. http://localhost:1234/v1/chat/completions'
                          : 'For Ollama e.g. http://localhost:11434',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _modelController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Model',
                    helperText: _type == ProviderType.gemma
                        ? 'Selected Gemma preset id'
                        : _type == ProviderType.webllm
                            ? 'Selected WebLLM model id'
                            : _type == ProviderType.local
                                ? 'Model id served by your local endpoint'
                                : 'e.g. gpt-4o-mini, llama3, mistral',
                  ),
                ),
                const SizedBox(height: 10),
                _ModelPresets(
                  type: _type,
                  onSelected: (model, baseUrl) {
                    _modelController.text = model;
                    _baseUrlController.text = baseUrl;
                  },
                ),
                if (_type == ProviderType.gemma) ...[
                  const SizedBox(height: 12),
                  _GemmaModelPresets(
                    service: widget.kbService.providerService.gemmaService,
                    selectedId: _modelController.text,
                    hfToken: _tokenController.text.trim(),
                    onSelected: (preset) {
                      setState(() => _modelController.text = preset.id);
                    },
                    onUse: () {
                      setState(() => _type = ProviderType.gemma);
                      _save();
                    },
                  ),
                ],
                if (_type == ProviderType.webllm) ...[
                  const SizedBox(height: 12),
                  _WebLlmModelPresets(
                    service: widget.kbService.providerService.webLlmService,
                    selectedId: _modelController.text,
                    onSelected: (preset) {
                      setState(() => _modelController.text = preset.id);
                    },
                    onUse: () {
                      setState(() => _type = ProviderType.webllm);
                      _save();
                    },
                  ),
                  const SizedBox(height: 12),
                  _WebLlmConfig(
                    contextWindowSize: _webLlmContextWindowSize,
                    maxOutputTokens: _webLlmMaxOutputTokens,
                    onContextWindowSizeChanged: (value) {
                      setState(() => _webLlmContextWindowSize = value);
                    },
                    onMaxOutputTokensChanged: (value) {
                      setState(() => _webLlmMaxOutputTokens = value);
                    },
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: GlowButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save settings'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _reset,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Reset KB'),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _message!.startsWith('Error')
                      ? AppColors.error
                      : AppColors.success,
                ),
              ),
            ),
          NeoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _StatusRow(
                  label: 'Provider',
                  value: settings.provider,
                  icon: Icons.cloud_outlined,
                ),
                _StatusRow(
                  label: 'Model',
                  value: settings.model.isEmpty ? '—' : settings.model,
                  icon: Icons.psychology_outlined,
                ),
                _StatusRow(
                  label: 'Token',
                  value: settings.apiKey.isEmpty ? 'not set' : 'saved',
                  icon: Icons.key_outlined,
                  valueColor: settings.apiKey.isEmpty ? AppColors.warning : AppColors.success,
                ),
                _StatusRow(
                  label: 'LLM ready',
                  value: configured ? 'yes' : 'no',
                  icon: Icons.bolt_outlined,
                  valueColor: configured ? AppColors.success : AppColors.textMuted,
                ),
                _StatusRow(
                  label: 'Records',
                  value: '$_recordCount',
                  icon: Icons.library_books_outlined,
                ),
                const Divider(color: AppColors.border),
                _VersionFooter(info: _versionInfo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tokenLabel() {
    return switch (_type) {
      ProviderType.ollama => 'Ollama token (optional)',
      ProviderType.openRouter => 'OpenRouter API key',
      ProviderType.openAi => 'OpenAI API key',
      ProviderType.local => 'API key (optional)',
      ProviderType.gemma => 'HuggingFace token (optional)',
      ProviderType.webllm => 'Token (unused)',
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
        webLlmContextWindowSize: _webLlmContextWindowSize,
        webLlmMaxOutputTokens: _webLlmMaxOutputTokens,
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
        backgroundColor: AppColors.surface,
        title: const Text(
          'Reset knowledge base?',
          style: TextStyle(color: AppColors.text),
        ),
        content: const Text(
          'This deletes all records, answers and notes from browser storage.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          GlowButton(
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

class _ModelPresets extends StatelessWidget {
  final ProviderType type;
  final void Function(String model, String baseUrl) onSelected;

  const _ModelPresets({required this.type, required this.onSelected});

  static const _presets = [
    (
      provider: 'openrouter',
      label: 'Gemini 2.5 Flash Lite (1M ctx)',
      model: 'google/gemini-2.5-flash-lite',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Gemini 3.1 Flash Lite (1M ctx)',
      model: 'google/gemini-3.1-flash-lite-preview',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Gemini 3.5 Flash (1M ctx)',
      model: 'google/gemini-3.5-flash',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Claude Sonnet 5 (1M ctx)',
      model: 'anthropic/claude-sonnet-5',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Claude 3 Haiku (200k ctx)',
      model: 'anthropic/claude-3-haiku',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Gemma 4 31B',
      model: 'google/gemma-4-31b-it',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Qwen 3.6 Flash',
      model: 'qwen/qwen3.6-flash',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Qwen 3 VL 8B',
      model: 'qwen/qwen3-vl-8b-instruct',
      baseUrl: '',
    ),
    (
      provider: 'openrouter',
      label: 'Qwen 3.5 Flash',
      model: 'qwen/qwen3.5-flash-02-23',
      baseUrl: '',
    ),
    (
      provider: 'openai',
      label: 'GPT-4o mini',
      model: 'gpt-4o-mini',
      baseUrl: '',
    ),
    (
      provider: 'openai',
      label: 'GPT-4o',
      model: 'gpt-4o',
      baseUrl: '',
    ),
    (
      provider: 'ollama',
      label: 'llama3',
      model: 'llama3',
      baseUrl: 'http://localhost:11434/v1/chat/completions',
    ),
    (
      provider: 'ollama',
      label: 'llava',
      model: 'llava',
      baseUrl: 'http://localhost:11434/v1/chat/completions',
    ),
    (
      provider: 'local',
      label: 'LM Studio / local',
      model: 'local-model',
      baseUrl: 'http://localhost:1234/v1/chat/completions',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _presets.where((p) => p.provider == type.settingsValue).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((p) {
        return ActionChip(
          label: Text(p.label),
          onPressed: () => onSelected(p.model, p.baseUrl),
          backgroundColor: AppColors.surfaceLow,
          side: const BorderSide(color: AppColors.border),
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        );
      }).toList(),
    );
  }
}

class _WebLlmModelPresets extends StatefulWidget {
  final WebLlmService service;
  final String selectedId;
  final ValueChanged<WebLlmModelPreset> onSelected;
  final VoidCallback? onUse;

  const _WebLlmModelPresets({
    required this.service,
    required this.selectedId,
    required this.onSelected,
    this.onUse,
  });

  @override
  State<_WebLlmModelPresets> createState() => _WebLlmModelPresetsState();
}

class _WebLlmModelPresetsState extends State<_WebLlmModelPresets> {
  final Map<String, bool> _cached = {};
  final Map<String, double> _progress = {};
  String? _loadingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshCachedStatus();
  }

  Future<void> _refreshCachedStatus() async {
    for (final preset in webLlmModelPresets) {
      final cached = await widget.service.isModelCached(preset.id);
      if (mounted) setState(() => _cached[preset.id] = cached);
    }
  }

  Future<void> _load(WebLlmModelPreset preset) async {
    setState(() {
      _loadingId = preset.id;
      _progress[preset.id] = 0;
      _error = null;
    });

    final progressSub = widget.service.progress.listen(
      (report) {
        // Progress events arrive as JS objects; avoid direct interop access in
        // shared widget code so VM tests compile without dart:js_interop.
        if (mounted) {
          setState(() => _progress[preset.id] = _progress[preset.id]! + 5);
        }
      },
      onError: (e) {
        if (mounted) setState(() => _error = 'Load failed: $e');
      },
    );

    try {
      await widget.service.loadModel(
        preset,
        contextWindowSize: preset.defaultContextWindow,
      );
      if (mounted) {
        setState(() => _cached[preset.id] = true);
        widget.onSelected(preset);
        widget.onUse?.call();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Load failed: $e');
    } finally {
      await progressSub.cancel();
      if (mounted) setState(() => _loadingId = null);
    }
  }

  Future<void> _delete(WebLlmModelPreset preset) async {
    setState(() {
      _loadingId = preset.id;
      _error = null;
    });
    try {
      await widget.service.deleteModel(preset.id);
      if (mounted) setState(() => _cached[preset.id] = false);
    } catch (e) {
      if (mounted) setState(() => _error = 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _loadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'On-device WebLLM models',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: webLlmModelPresets.map((preset) {
            final isSelected = widget.selectedId == preset.id;
            final cached = _cached[preset.id] == true;
            final loading = _loadingId == preset.id;
            final progress = _progress[preset.id] ?? 0;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Tooltip(
                message: '${preset.displayName}\n${preset.size}',
                child: InputChip(
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        preset.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        preset.size,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (loading)
                        LinearProgressIndicator(
                          value: progress > 0 ? progress / 100 : null,
                          backgroundColor: AppColors.surfaceLow,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: cached
                      ? (_) {
                          widget.onSelected(preset);
                          widget.onUse?.call();
                        }
                      : (_) => widget.onSelected(preset),
                  deleteIcon: loading
                      ? const SizedBox.shrink()
                      : cached
                          ? const Icon(Icons.delete, size: 16)
                          : const Icon(Icons.download, size: 16),
                  onDeleted: loading
                      ? null
                      : cached
                          ? () => _delete(preset)
                          : () => _load(preset),
                ),
              ),
            );
          }).toList(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _WebLlmConfig extends StatelessWidget {
  final int contextWindowSize;
  final int maxOutputTokens;
  final ValueChanged<int> onContextWindowSizeChanged;
  final ValueChanged<int> onMaxOutputTokensChanged;

  const _WebLlmConfig({
    required this.contextWindowSize,
    required this.maxOutputTokens,
    required this.onContextWindowSizeChanged,
    required this.onMaxOutputTokensChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'WebLLM context',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Context window: $contextWindowSize',
                    style: const TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                  Slider(
                    value: contextWindowSize.toDouble(),
                    min: 512,
                    max: 8192,
                    divisions: 15,
                    label: contextWindowSize.toString(),
                    onChanged: (value) =>
                        onContextWindowSizeChanged(value.toInt()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Max output tokens: $maxOutputTokens',
                    style: const TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                  Slider(
                    value: maxOutputTokens.toDouble(),
                    min: 128,
                    max: 4096,
                    divisions: 15,
                    label: maxOutputTokens.toString(),
                    onChanged: (value) =>
                        onMaxOutputTokensChanged(value.toInt()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GemmaModelPresets extends StatefulWidget {
  final GemmaService service;
  final String selectedId;
  final String hfToken;
  final ValueChanged<GemmaModelPreset> onSelected;
  final VoidCallback? onUse;

  const _GemmaModelPresets({
    required this.service,
    required this.selectedId,
    required this.hfToken,
    required this.onSelected,
    this.onUse,
  });

  @override
  State<_GemmaModelPresets> createState() => _GemmaModelPresetsState();
}

class _GemmaModelPresetsState extends State<_GemmaModelPresets> {
  final Map<String, bool> _installed = {};
  final Map<String, double> _progress = {};
  String? _installingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshInstalledStatus();
  }

  Future<void> _refreshInstalledStatus() async {
    for (final preset in gemmaModelPresets) {
      final installed = await widget.service.isModelInstalled(preset);
      if (mounted) {
        setState(() => _installed[preset.id] = installed);
      }
    }
  }

  Future<void> _install(GemmaModelPreset preset) async {
    setState(() {
      _installingId = preset.id;
      _progress[preset.id] = 0;
      _error = null;
    });
    try {
      await for (final value in widget.service.installModel(preset, hfToken: widget.hfToken)) {
        if (mounted) {
          setState(() => _progress[preset.id] = value);
        }
      }
      if (mounted) {
        setState(() => _installed[preset.id] = true);
        widget.onSelected(preset);
        widget.onUse?.call();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Install failed: $e');
    } finally {
      if (mounted) setState(() => _installingId = null);
    }
  }

  Future<void> _delete(GemmaModelPreset preset) async {
    setState(() {
      _installingId = preset.id;
      _error = null;
    });
    try {
      await widget.service.deleteModel(preset);
      if (mounted) {
        setState(() => _installed[preset.id] = false);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _installingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'On-device models',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: gemmaModelPresets.map((preset) {
            final isSelected = widget.selectedId == preset.id;
            final installed = _installed[preset.id] == true;
            final installing = _installingId == preset.id;
            final progress = _progress[preset.id] ?? 0;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Tooltip(
                message: '${preset.displayName}\n${preset.bestFor}',
                child: InputChip(
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        preset.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        preset.size,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (installing)
                        LinearProgressIndicator(
                          value: progress > 0 ? progress / 100 : null,
                          backgroundColor: AppColors.surfaceLow,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: installed
                      ? (_) {
                          widget.onSelected(preset);
                          widget.onUse?.call();
                        }
                      : (_) => widget.onSelected(preset),
                  deleteIcon: installing
                      ? const SizedBox.shrink()
                      : installed
                          ? const Icon(Icons.delete, size: 16)
                          : const Icon(Icons.download, size: 16),
                  onDeleted: installing
                      ? null
                      : installed
                          ? () => _delete(preset)
                          : () => _install(preset),
                ),
              ),
            );
          }).toList(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _ProviderGrid extends StatelessWidget {
  final ProviderType selected;
  final ValueChanged<ProviderType> onSelected;

  const _ProviderGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final options = [
      (ProviderType.ollama, 'Ollama', Icons.computer),
      (ProviderType.openRouter, 'OpenRouter', Icons.router),
      (ProviderType.openAi, 'OpenAI', Icons.bolt),
      (ProviderType.local, 'Local server', Icons.home),
      (ProviderType.gemma, 'Flutter Gemma', Icons.memory),
      (ProviderType.webllm, 'WebLLM', Icons.web),
      (ProviderType.none, 'None', Icons.block),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final isSelected = selected == o.$1;
        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(o.$3, size: 16, color: isSelected ? AppColors.text : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(o.$2),
            ],
          ),
          selected: isSelected,
          onSelected: (_) => onSelected(o.$1),
          selectedColor: AppColors.primary.withValues(alpha: 0.25),
          backgroundColor: AppColors.surfaceLow,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.text : AppColors.textMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: isSelected ? AppColors.primaryGlow : AppColors.border,
          ),
        );
      }).toList(),
    );
  }
}

class _ProviderHint extends StatelessWidget {
  final ProviderType type;
  const _ProviderHint({required this.type});

  @override
  Widget build(BuildContext context) {
    if (type == ProviderType.ollama) {
      return _HintCard(
        icon: Icons.open_in_new,
        text: 'Get Ollama',
        url: 'https://github.com/ollama/ollama',
        subtext: 'Run with OLLAMA_ORIGINS=* ollama serve to avoid CORS.',
      );
    }
    if (type == ProviderType.openRouter) {
      return _HintCard(
        icon: Icons.open_in_new,
        text: 'Get OpenRouter key',
        url: 'https://openrouter.ai/keys',
      );
    }
    if (type == ProviderType.openAi) {
      return _HintCard(
        icon: Icons.open_in_new,
        text: 'Get OpenAI key',
        url: 'https://platform.openai.com/api-keys',
      );
    }
    if (type == ProviderType.local) {
      return _HintCard(
        icon: Icons.info_outline,
        text: 'Local OpenAI-compatible endpoint',
        url: 'https://platform.openai.com/docs/api-reference/chat/create',
        subtext: 'Use the full /v1/chat/completions URL and a model id served by your endpoint.',
      );
    }
    if (type == ProviderType.gemma) {
      return _HintCard(
        icon: Icons.open_in_new,
        text: 'Flutter Gemma models',
        url: 'https://fluttergemma.dev',
      );
    }
    if (type == ProviderType.webllm) {
      return _HintCard(
        icon: Icons.open_in_new,
        text: 'WebLLM model list',
        url: 'https://github.com/mlc-ai/web-llm',
      );
    }
    return const SizedBox.shrink();
  }
}

class _HintCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final String url;
  final String? subtext;

  const _HintCard({
    required this.icon,
    required this.text,
    required this.url,
    this.subtext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Link(
            uri: Uri.parse(url),
            builder: (context, followLink) => TextButton.icon(
              onPressed: followLink,
              icon: Icon(icon, size: 18, color: AppColors.secondaryGlow),
              label: Text(text, style: const TextStyle(color: AppColors.secondaryGlow)),
            ),
          ),
          if (subtext != null)
            Text(
              subtext!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatusRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  final DemoVersionInfo? info;

  const _VersionFooter({this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        info?.format() ?? 'Loading version info...',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
