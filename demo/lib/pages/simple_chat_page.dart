import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agent_memory/flutter_agent_memory_web.dart';

import '../services/kb_service.dart';
import '../theme/app_theme.dart';

/// Minimal chat UI for talking to the currently configured LLM provider.
///
/// Unlike the rest of the demo, this page does not store records or run
/// extraction pipelines; it just sends user messages and displays replies.
class SimpleChatPage extends StatefulWidget {
  final KbService kbService;

  const SimpleChatPage({super.key, required this.kbService});

  @override
  State<SimpleChatPage> createState() => _SimpleChatPageState();
}

class _SimpleChatPageState extends State<SimpleChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _running = false;

  LlmProvider? get _provider => widget.kbService.providerService.provider;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final provider = _provider;
    if (provider == null) {
      _addMessage(role: 'system', text: 'No provider configured. Go to Settings first.');
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _running = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await provider.chat(text);
      setState(() => _messages.add(_ChatMessage(role: 'assistant', text: response.trim())));
    } catch (e, s) {
      setState(() => _messages.add(_ChatMessage(role: 'system', text: 'Error: $e\n$s')));
    } finally {
      setState(() => _running = false);
      _scrollToBottom();
    }
  }

  void _addMessage({required String role, required String text}) {
    setState(() => _messages.add(_ChatMessage(role: role, text: text)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final modelLabel = widget.kbService.settings.model.isEmpty
        ? 'No model'
        : widget.kbService.settings.model;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: AppColors.primaryGlow),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Simple chat',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Model: ${widget.kbService.settings.provider} / $modelLabel',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (provider != null)
                TextButton.icon(
                  onPressed: _messages.isEmpty ? null : () {
                    Clipboard.setData(ClipboardData(
                      text: _messages.map((m) => '${m.role}: ${m.text}').join('\n\n'),
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider == null)
            NeoCard(
              gradientColors: [
                AppColors.warning.withValues(alpha: 0.3),
                AppColors.warning.withValues(alpha: 0.05),
              ],
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Configure a provider and model in Settings first.',
                      style: TextStyle(
                        color: AppColors.text.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: NeoCard(
                child: Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? Center(
                              child: Text(
                                'Start a conversation with the selected model.',
                                style: TextStyle(
                                  color: AppColors.textMuted.withValues(alpha: 0.7),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                return _MessageBubble(message: _messages[index]);
                              },
                            ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              enabled: !_running,
                              minLines: 1,
                              maxLines: 6,
                              style: const TextStyle(color: AppColors.text),
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(color: AppColors.textMuted),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GlowButton(
                            icon: _running ? Icons.hourglass_top : Icons.send,
                            onPressed: _running ? null : _send,
                            child: Text(_running ? 'Running' : 'Send'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String text;

  _ChatMessage({required this.role, required this.text});
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  Color get _bubbleColor {
    return switch (message.role) {
      'user' => AppColors.surfaceHigh,
      'assistant' => AppColors.surface,
      _ => AppColors.background,
    };
  }

  Color get _roleColor {
    return switch (message.role) {
      'user' => AppColors.primaryGlow,
      'assistant' => AppColors.secondaryGlow,
      _ => AppColors.error,
    };
  }

  String get _roleLabel {
    return switch (message.role) {
      'user' => 'You',
      'assistant' => 'Model',
      _ => 'System',
    };
  }

  Alignment get _alignment {
    return switch (message.role) {
      'user' => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _bubbleColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _roleLabel,
                style: TextStyle(
                  color: _roleColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                message.text,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
