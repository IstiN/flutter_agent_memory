/// Web-safe subset of `flutter_agent_memory`.
///
/// Import this library in Flutter web apps or other web targets. It avoids
/// `dart:io` dependencies while exposing the core knowledge-base store,
/// search, graph builder, and pluggable storage adapters.
library flutter_agent_memory_web;

// Agents (prompt loader is host-configurable, so it is web-safe).
export 'src/agents/kb_tag_generator_agent.dart';
export 'src/agents/kb_reranker_agent.dart';
export 'src/agents/prompts/prompt_loader.dart';

// LLM.
export 'src/llm/llm_config.dart';
export 'src/llm/llm_message.dart';
export 'src/llm/llm_provider.dart';
export 'src/llm/openai_provider.dart';
export 'src/llm/openrouter_provider.dart';
export 'src/llm/provider_factory.dart';

// Models.
export 'src/models/answer.dart';
export 'src/models/kb_context.dart';
export 'src/models/link.dart';
export 'src/models/memory_level.dart';
export 'src/models/memory_type.dart';
export 'src/models/note.dart';
export 'src/models/question.dart';
export 'src/models/relation.dart';

// Search.
export 'src/search/kb_search_engine.dart';
export 'src/search/kb_search_result.dart';
export 'src/search/kb_text_search_result.dart';

// Storage.
export 'src/storage/http_kb_storage.dart';
export 'src/storage/in_memory_kb_storage.dart';
export 'src/storage/kb_graph_builder.dart';
export 'src/storage/kb_markdown_renderer.dart';
export 'src/storage/kb_memory_store.dart';
export 'src/storage/kb_storage.dart';
export 'src/storage/kb_storage_context_mixin.dart';
export 'src/storage/web/web_kb_storage.dart';
