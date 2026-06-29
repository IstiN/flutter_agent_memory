# flutter_agent_memory

![Build](https://github.com/IstiN/flutter_agent_memory/actions/workflows/build.yml/badge.svg?branch=main)

A Dart memory/knowledge-base library inspired by the Java `dmtools-core` KB module.

It turns unstructured conversations, docs, or notes into a structured,
Obsidian-compatible Markdown knowledge base of **questions**, **answers**,
**notes**, and **people**, powered by any OpenAI-compatible LLM (OpenAI,
OpenRouter, Ollama, etc.).

---

## Table of contents

- [What it does](#what-it-does)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Installation](#installation)
- [CLI reference](#cli-reference)
- [Library API](#library-api)
- [Searching the knowledge base](#searching-the-knowledge-base)
- [Integrating into your project](#integrating-into-your-own-project)
- [Output structure](#output-structure)
- [Provider configuration](#provider-configuration)
- [Running tests](#running-tests)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## What it does

1. **Ingest** raw text (chat logs, meeting notes, docs).
2. **Extract** questions, answers, and notes with an LLM.
3. **Link** answers to questions and notes to questions.
4. **Build** a Markdown knowledge base:
   - `questions/`, `answers/`, `notes/`
   - `topics/`, `areas/`, `people/`
   - `stats/`, `INDEX.md`
5. **Search** by explicit tags or by natural language (AI generates tags from the query).

Everything is stored as plain Markdown with YAML frontmatter, so the result can
be opened directly in Obsidian, GitHub, or any text editor.

---

## Architecture

```mermaid
graph LR
  A[Raw text] --> B[KBAnalysisAgent]
  B --> C[AnalysisResult]
  C --> D[KBAnalysisValidator]
  D --> E[KBQAMappingService]
  E --> F[KBIdMapper]
  F --> G[KBStructureManager]
  G --> H[Markdown KB]
  H --> I[KBSearchEngine]
  I --> J[Search results]
```

Key components:

| Component | Purpose |
|-----------|---------|
| `LlmProvider` | Abstraction over any OpenAI-compatible chat API. |
| `KBAnalysisAgent` | Extracts Q/A/N from text. |
| `KBQuestionAnswerMappingAgent` | Matches new answers to existing unanswered questions. |
| `KBAggregationAgent` | Generates narrative descriptions for people/topics/areas. |
| `KBTagGeneratorAgent` | Generates search tags from natural-language queries. |
| `KBStructureManager` | Writes and updates the Markdown structure. |
| `KBSearchEngine` | Tag-based and AI-assisted text search. |
| `KBOrchestrator` | Runs the whole pipeline end-to-end. |

---

## Quick start

```bash
# 1. Clone or depend on the package
git clone https://github.com/IstiN/flutter_agent_memory.git
cd flutter_agent_memory
dart pub get

# 2. Create a .env file with your LLM credentials
cat > .env <<EOF
OLLAMA_BASE_URL=https://ollama.com
OLLAMA_MODEL=ministral-3:14b
OLLAMA_API_KEY=your_key_here
EOF

# 3. Process a text file
dart run bin/agent_memory.dart process -i example/input.md -o my_kb -s docs --verbose

# 4. Search the generated knowledge base
dart run bin/agent_memory.dart search -o my_kb -q "How do I test Dart code?" --show-tags
```

If you installed the CLI via the install script, replace `dart run bin/agent_memory.dart`
with `agent_memory` in the commands above.

---

## Installation

### CLI via install script

The fastest way to use `agent_memory` as a system command. The installer downloads
and installs the Dart SDK only if it is not already available, compiles a native
binary, and puts the `agent_memory` command on your PATH.

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/IstiN/flutter_agent_memory/main/install | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/IstiN/flutter_agent_memory/main/scripts/install.ps1 | iex
```

On macOS/Linux the installer first tries to place the wrapper into a directory
already on your PATH (`~/.local/bin` or `~/bin`), so `agent_memory` is available
immediately. If neither exists, it installs into `~/.flutter_agent_memory/bin`
and appends that directory to your shell profile.

After installation, run:

```bash
agent_memory --help
```

You can customize the install location, binary location, and Dart version:

```bash
FAM_INSTALL_DIR=/opt/fam FAM_BIN_DIR=/usr/local/bin FAM_DART_VERSION=3.10.8 bash -c 'curl -fsSL https://raw.githubusercontent.com/IstiN/flutter_agent_memory/main/install | bash'
```

To use a local copy of the repository instead of cloning from GitHub:

```bash
FAM_REPO_DIR=/path/to/flutter_agent_memory bash scripts/install.sh
```

### Prebuilt binaries from CI

Every commit to `main` compiles native binaries for Linux, macOS, and Windows. You
can download them from the latest successful **Build and test** workflow run:

```text
GitHub → Actions → Build and test → <latest run on main> → Artifacts
```

Artifacts include:

- `agent_memory-linux-x64`
- `agent_memory-macos-arm64` / `agent_memory-macos-x64`
- `agent_memory-windows-x64.exe`
- `install-scripts` — the installer bootstrap, install scripts, and dev wrappers

Release tags also publish these files as release assets automatically.

### Development wrapper

If you are hacking on the project, use the included wrapper scripts so you do not
need to install anything globally:

```bash
# macOS / Linux
./scripts/agent_memory.sh --help

# Windows
scripts\agent_memory.bat --help
.\scripts\agent_memory.ps1 --help
```

The CLI automatically loads a `.env` file from the current working directory, so
place your LLM credentials there.

### As a Dart/Flutter dependency

```bash
dart pub add flutter_agent_memory
```

Or use the Git version:

```yaml
dependencies:
  flutter_agent_memory:
    git:
      url: https://github.com/IstiN/flutter_agent_memory.git
```

```bash
dart pub get
```

### CLI from source

The CLI entry point is `bin/agent_memory.dart`. You can run it directly or
activate it globally:

```bash
dart pub global activate --source path .
agent_memory process -i input.md -o kb
```

---

## CLI reference

All commands support `--help` for detailed options. For a structured cheat-sheet
aimed at LLM agents (what the framework does, how to configure providers, and
how to call each command), run:

```bash
agent_memory skill
```

Use `agent_memory skill -f json` for a machine-readable version.

### `skill` — LLM agent cheat-sheet

Prints a Markdown description of the framework, provider setup, every command,
and their parameters. Useful for giving an LLM context about how to invoke
`agent_memory`.

```bash
agent_memory skill
agent_memory skill -f json
```

### `process` — build or update the KB

`process` accepts a single text file, an image, a directory of files, or stdin.
Images are base64-encoded and sent to vision-capable models.

```bash
# Text file
dart run bin/agent_memory.dart process -i meeting.md -o kb -s meeting --verbose

# Image (screenshot, diagram, photo of a whiteboard)
dart run bin/agent_memory.dart process -i screenshot.png -o kb -s whiteboard --provider openai --model gpt-4o

# Directory of files (each supported file becomes a separate source)
dart run bin/agent_memory.dart process -i ./docs -o kb --verbose

# stdin
cat chat_export.json | dart run bin/agent_memory.dart process -i - -o kb -s telegram
```

Supported file types:
- **Text**: `.txt`, `.md`, `.json`, `.yaml`, `.csv`, `.log`, code files, etc.
- **Images**: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.bmp`

Options:
- `-i, --input` — input file, directory, or `-` for stdin
- `-o, --output` — output directory (default: `kb`)
- `-s, --source` — source name (for single input; derived from filename otherwise)
- `--provider` — `openai`, `openrouter` or `ollama` (default: `openai`)
- `--api-key`, `--base-url`, `--model`, `--max-tokens`, `--temperature`
- `--mode` — `full`, `process-only`, `aggregate-only`
- `--clean` — wipe output directory before processing

### `regenerate` — rebuild structure/indexes from existing files

```bash
dart run bin/agent_memory.dart regenerate -o kb -s manual_edit
```

### `stats` — regenerate statistics and indexes

```bash
dart run bin/agent_memory.dart stats -o kb
```

### `search-tags` — explicit tag search

```bash
# All listed tags must match
dart run bin/agent_memory.dart search-tags -o kb -t "dart,unit-tests"

# Any listed tag can match
dart run bin/agent_memory.dart search-tags -o kb -t "dart,flutter" --match-any

# Only answers
dart run bin/agent_memory.dart search-tags -o kb -t "dart" --type answer

# JSON output
dart run bin/agent_memory.dart search-tags -o kb -t "dart" --json
```

### `search` — natural-language search (AI-generated tags)

```bash
# Basic search
dart run bin/agent_memory.dart search -o kb -q "How do I test Dart code?"

# Show which tags the AI generated
dart run bin/agent_memory.dart search -o kb -q "testing in Dart" --show-tags

# Require all generated tags to match (more strict)
dart run bin/agent_memory.dart search -o kb -q "Flutter state management" --match-all

# JSON output for scripting
dart run bin/agent_memory.dart search -o kb -q "CI/CD" --json
```

Example output:

```text
Generated tags: ci-cd, flutter, github-actions, unit-tests, test-package

Found 2 record(s):

- [question] q_0004: What CI/CD tool do you recommend for Flutter apps?
  path: kb/questions/q_0004.md
  matched tags: ci-cd, flutter, github-actions

- [answer] a_0004: GitHub Actions works well. Use actions/checkout, install Flutter, and run flutter test and flutter build.
  path: kb/answers/a_0004.md
  matched tags: ci-cd, flutter, github-actions
```

### `memory` — agent memory CRUD

Store, query, and manage small facts for an agent. Each operation works against
a knowledge-base directory (default: `kb`).

```bash
# Add a note
agent_memory memory add -t note -x "Use Result<T,E> for explicit error handling"

# Add a question and an answer
agent_memory memory add -t question -x "How do I handle async errors in Dart?"
agent_memory memory add -t answer -x "Use try/catch or Result/AsyncError wrappers" \
  --answers-question q_0001

# Ask the memory
agent_memory memory ask -q "How do I handle async errors?"

# List records
agent_memory memory list --limit 20

# Top records by access count
agent_memory memory rank --sort accessCount --limit 10

# Update / delete
agent_memory memory update -i n_0001 -x "Updated note text" --tags dart,errors
agent_memory memory delete -i n_0001
```

### Batch processing

```bash
for f in sources/*.md; do
  name=$(basename "$f" .md)
  dart run bin/agent_memory.dart process -i "$f" -o kb -s "$name"
done

dart run bin/agent_memory.dart stats -o kb
```

### Processing from stdin

```bash
cat chat_export.json | dart run bin/agent_memory.dart process -i - -o kb -s telegram
```

---

## Library API

### Run the full pipeline

```dart
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

Future<void> buildKb() async {
  final config = LlmConfig.fromEnvironment(provider: 'openai');
  final provider = ProviderFactory.create(config);

  final orchestrator = KBOrchestrator(provider);
  final result = await orchestrator.run(KBOrchestratorParams(
    sourceName: 'team_chat',
    inputText: '''
[2024-11-15T09:30:00Z] Alice: How do I write unit tests in Dart?
[2024-11-15T09:32:00Z] Bob: Use the test package.
''',
    outputPath: 'kb',
    processingMode: KBProcessingMode.processOnly,
  ));

  print('Questions: ${result.questionsCount}');
  print('Answers:   ${result.answersCount}');
}
```

### Process an image

```dart
import 'dart:io';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

Future<void> processImage(String imagePath) async {
  final inputs = await InputLoader().load(imagePath);
  final input = inputs.first;

  final config = LlmConfig.fromEnvironment();
  final provider = ProviderFactory.create(config);
  final orchestrator = KBOrchestrator(provider);

  final result = await orchestrator.run(KBOrchestratorParams(
    sourceName: 'whiteboard',
    inputText: input.promptText,
    inputImages: input.images ?? const [],
    outputPath: 'kb',
  ));

  print('Extracted ${result.questionsCount} questions');
}
```

### Use a custom LLM provider

```dart
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

class MyProvider implements LlmProvider {
  @override
  String get defaultModel => 'custom-model';

  @override
  Future<String> chat(String prompt, {String? model}) async {
    // Call your own endpoint.
    return '...';
  }

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async {
    return chat(messages.map((m) => m.content).join('\n'));
  }
}

final orchestrator = KBOrchestrator(MyProvider());
```

### Configure Ollama

```dart
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

final provider = OpenAiProvider(
  apiKey: 'your_ollama_key',
  baseUrl: 'https://ollama.com/v1/chat/completions',
  defaultModel: 'ministral-3:14b',
  maxTokens: 2048,
);

final orchestrator = KBOrchestrator(provider);
```

### Use agents directly

```dart
final provider = ProviderFactory.create(LlmConfig.fromEnvironment());

// Extract Q/A/N
final analysis = await KBAnalysisAgent(provider).analyze(
  'Alice: How to test Dart?\nBob: Use the test package.',
  KBContext(),
  sourceName: 'chat',
);

// Map answers to existing questions
final mappings = await KBQuestionAnswerMappingAgent(provider).mapAnswers(
  analysis,
  KBContext(),
);

// Generate a topic description
final description = await KBAggregationAgent(provider).aggregate(
  'topic',
  'dart-testing',
  'Questions and answers about Dart testing.',
);
```

### Work with models

```dart
final question = Question(
  id: 'q_0001',
  author: 'Alice',
  text: 'How do I test Dart code?',
  date: '2024-11-15T09:30:00Z',
  area: 'development',
  topics: ['dart-testing'],
  tags: ['unit-tests'],
  answeredBy: 'a_0001',
  links: [],
);

final json = question.toJson();
final restored = Question.fromJson(json);
```

### Read KB files

```dart
import 'dart:io';

final question = KBFileParser().parseQuestion(
  File('kb/questions/q_0001.md').readAsStringSync(),
);
```

---

## Searching the knowledge base

### Tag search

```dart
import 'dart:io';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

final engine = KBSearchEngine(Directory('kb'));

final exact = engine.searchByTags(['dart', 'unit-tests']);
final broad = engine.searchByTags(['dart', 'flutter'], matchAll: false);
final answersOnly = engine.searchByTags(['dart'], entityTypes: ['answer']);
```

### Natural-language search

```dart
final config = LlmConfig.fromEnvironment();
final provider = ProviderFactory.create(config);
final engine = KBSearchEngine(Directory('kb'), provider: provider);

final result = await engine.searchByText(
  'How do I write unit tests in Dart?',
  matchAll: false,
);

print('Generated tags: ${result.generatedTags}');
for (final r in result.results) {
  print('${r.entityType} ${r.id}: ${r.title}');
}
```

The engine:
1. Collects all existing tags from the KB.
2. Asks the LLM to generate relevant tags from the query.
3. Runs a tag search with the generated tags.

Results are ranked by a combined score: tag matches + access frequency +
importance + recency.

---

## Agent memory store

Agents can add, update, delete, and query individual records directly, without
re-running the full analysis pipeline.

### Library API

```dart
import 'dart:io';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

final store = KBMemoryStore(Directory('kb'), source: 'my_agent');

// Add records
final question = await store.addQuestion(
  text: 'How do I cache images in Flutter?',
  area: 'development',
  tags: ['flutter', 'caching'],
  importance: 0.8,
);

final answer = await store.addAnswer(
  text: 'Use cached_network_image.',
  area: 'development',
  tags: ['flutter', 'caching'],
  answersQuestion: question.id,
);

final note = await store.addNote(
  text: 'Remember to handle cache eviction.',
  area: 'development',
  tags: ['flutter', 'caching'],
);

// Record access (updates ranking)
store.recordAccess(question.id);

// List and rank
final recent = store.list(sortBy: 'lastAccessed', limit: 10);
final top = store.list(sortBy: 'accessCount', limit: 10);

// Update / delete
await store.updateRecord(question.id, text: 'How do I cache images?');
store.deleteRecord(question.id);
```

### CLI

```bash
# Add a note
dart run bin/agent_memory.dart memory add -o kb -t note \
  --text "Always pin dependency versions." \
  --tags "workflow,dart" --area development

# Ask the memory a question (AI generates tags, ranks, and tracks access)
dart run bin/agent_memory.dart memory ask -o kb \
  -q "How should I manage Dart dependencies?" --provider ollama

# List recent records
dart run bin/agent_memory.dart memory list -o kb --limit 10

# Show most frequently used records
dart run bin/agent_memory.dart memory rank -o kb --sort accessCount --limit 5

# Delete a record
dart run bin/agent_memory.dart memory delete -o kb -i n_0001

# Update a record
dart run bin/agent_memory.dart memory update -o kb -i n_0001 \
  --text "Always pin dependency versions and use lock files." \
  --tags "workflow,dart,pubspec"
```

### Memory metadata

Every record tracks:

| Field | Meaning |
|-------|---------|
| `accessCount` | How many times the record was accessed. |
| `lastAccessedAt` | ISO timestamp of the last access. |
| `importance` | Manual or LLM-assigned score 0.0-1.0. |

These fields are stored in YAML frontmatter and influence search ranking.

---

## Integrating into your own project

### Minimal Dart integration

```dart
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

Future<KBResult> buildKbFromText(String sourceName, String text) async {
  final config = LlmConfig.fromEnvironment();
  final provider = ProviderFactory.create(config);
  final orchestrator = KBOrchestrator(provider);

  return orchestrator.run(KBOrchestratorParams(
    sourceName: sourceName,
    inputText: text,
    outputPath: 'kb',
  ));
}
```

### Flutter integration example

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

class BuildKbButton extends StatelessWidget {
  const BuildKbButton({super.key});

  Future<void> _onPressed(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';

    final config = LlmConfig.fromEnvironment();
    final provider = ProviderFactory.create(config);
    final result = await KBOrchestrator(provider).run(KBOrchestratorParams(
      sourceName: 'clipboard',
      inputText: text,
      outputPath: 'kb',
    ));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KB built: ${result.questionsCount} questions')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _onPressed(context),
      child: const Text('Build KB from clipboard'),
    );
  }
}
```

### Custom backend provider

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_agent_memory/flutter_agent_memory.dart';

class MyBackendProvider implements LlmProvider {
  @override
  String get defaultModel => 'custom-model';

  @override
  Future<String> chat(String prompt, {String? model}) async {
    final response = await http.post(
      Uri.parse('https://my-llm.example.com/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    );
    return jsonDecode(response.body)['text'];
  }

  @override
  Future<String> chatMessages(List<LlmMessage> messages, {String? model}) async {
    return chat(messages.map((m) => m.content).join('\n'));
  }
}
```

---

## Output structure

```
kb/
├── answers/
│   └── a_0001.md
├── areas/
│   └── development/
│       ├── development.md
│       └── development-desc.md
├── inbox/
│   ├── raw/
│   │   └── <source>.md
│   ├── analyzed/
│   │   └── <source>_analyzed.json
│   └── source_config.json
├── notes/
├── people/
│   ├── Alice/
│   │   ├── Alice.md
│   │   └── Alice-desc.md
│   └── people.md
├── questions/
│   └── q_0001.md
├── stats/
│   ├── activity_timeline.md
│   └── topics_overview.md
├── topics/
│   └── dart-testing.md
└── INDEX.md
```

---

## Provider configuration

The library and CLI read configuration from environment variables. For local
development, put them in a `.env` file in the project root (`.env` is ignored
by git).

Example `.env` for Ollama:

```bash
OLLAMA_BASE_URL=https://ollama.com
OLLAMA_MODEL=ministral-3:14b
OLLAMA_API_KEY=your_key_here
```

Then use `--provider ollama`:

```bash
dart run bin/agent_memory.dart process -i input.md -o kb --provider ollama
dart run bin/agent_memory.dart search -o kb -q "testing in Dart" --provider ollama --show-tags
```

Example `.env` for OpenAI:

```bash
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o
```

Example `.env` for OpenRouter:

```bash
OPENROUTER_API_KEY=sk-or-...
OPENROUTER_MODEL=openai/gpt-4o
```

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` / `OPENROUTER_API_KEY` / `OLLAMA_API_KEY` | API key |
| `OPENAI_BASE_PATH` / `OPENROUTER_BASE_PATH` / `OLLAMA_BASE_URL` | Chat completions endpoint |
| `OPENAI_MODEL` / `OPENROUTER_MODEL` / `OLLAMA_MODEL` | Model name |
| `OPENAI_MAX_TOKENS` / `OPENROUTER_MAX_TOKENS` / `OLLAMA_MAX_TOKENS` | Max output tokens |
| `OPENAI_TEMPERATURE` / `OPENROUTER_TEMPERATURE` / `OLLAMA_TEMPERATURE` | Sampling temperature |
| `OPENAI_MAX_TOKENS_PARAM_NAME` | Max-tokens field name (default `max_completion_tokens`) |

`.env` values are loaded automatically when environment variables are not set.

---

## Running tests

Unit tests:

```bash
dart test
```

Integration tests read credentials from `.env`. They cover both the full
build pipeline and AI-generated tag search:

```bash
# Make sure .env exists and contains OLLAMA_* variables
dart test --tags integration
```

Preserve integration-test output for inspection:

```bash
KEEP_OUTPUT=true dart test --tags integration
# output will be in test_output/ollama_kb
```

---

## Troubleshooting

### `Provider is not configured`

Set the provider environment variables or pass `--api-key` and `--model`.

### `searchByText requires an LLM provider`

`KBSearchEngine.searchByText` needs a provider because it uses an LLM to
generate tags. Pass one:

```dart
KBSearchEngine(Directory('kb'), provider: provider)
```

### Empty analysis results

- Increase `--max-tokens`.
- Add `--analysis-instructions` to guide the model.
- Check that the input text is not empty or malformed.

### Ollama returns 404

Make sure the base URL ends with `/v1/chat/completions`:

```bash
--base-url "https://ollama.com/v1/chat/completions"
```

---

## License

See [LICENSE](LICENSE).
