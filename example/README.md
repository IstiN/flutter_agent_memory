# agent_memory example

This example shows how to use `agent_memory` as a Dart library to process a
small text snippet into a Markdown knowledge base and then search it.

## Run

Set your OpenAI credentials:

```bash
export OPENAI_API_KEY=sk-...
export OPENAI_MODEL=gpt-4o
```

Then run:

```bash
cd example
dart run main.dart
```

The example creates an `example_kb/` directory with extracted questions,
answers, notes, topics, areas, and people.
