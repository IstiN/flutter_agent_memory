# Landing Page Visual Design Prompt — Flutter Agent Memory

Generate a high-fidelity, modern landing page design mockup for **Flutter Agent Memory** — a Dart library, CLI, and web demo that turns unstructured text, images, voice transcripts, and directories into a structured Markdown knowledge base powered by any OpenAI-compatible LLM.

## Product essence

- **Core promise:** "Agent memory that thinks in questions, answers, notes, and connections."
- **What it does:**
  - Ingests raw text, images, meeting transcripts, VTT files, and whole directories.
  - Uses an LLM to extract questions, answers, notes, tags, topics, areas, and authors.
  - Stores everything as plain Markdown files (Obsidian-compatible).
  - Builds an interactive graph view where records cluster around shared tags, topics, areas, and people.
  - Supports semantic search by tags and natural-language text.
  - Works as a Dart library, a cross-platform CLI binary, and a Flutter web demo.
  - Plugs into OpenAI, OpenRouter, or **local Ollama models** — keep data on your machine.

## Privacy / local-first angle

Highlight that users are not locked into a cloud provider. The tool can run entirely offline with a local LLM, so sensitive meeting transcripts, research notes, and project knowledge never leave the device unless the user chooses.

## Target audience

Developers, AI-agent builders, research teams, and power users who want a durable, queryable, LLM-ready memory layer for their projects.

## Desired visual style

- **Theme:** Dark mode premium SaaS.
- **Color palette:** Deep charcoal/slate background (`#0B0E14`), subtle surface panels (`#111827` / `#1A1F2E`), vibrant accent gradients from electric violet (`#7C3AED`) through cyan (`#06B6D4`) to magenta (`#D946EF`).
- **Mood:** Futuristic, calm, intelligent, agentic.
- **Effects:** Soft glassmorphism, subtle glows, radial gradients, floating particles / constellation nodes, clean sans-serif typography (Inter / SF Pro style).
- **Layout:** Responsive desktop-first, 1440px container, generous whitespace, rounded corners (`16–24px`), thin borders with low-opacity accent color.

## Sections to include in the design

1. **Navbar** — logo mark (abstract memory graph icon), nav links (Features, Demo, CLI, Docs, GitHub), primary CTA button "Try the demo".
2. **Hero** — big headline "Give your agent a memory that lasts", subheadline about Markdown KB + LLM, two CTAs ("Open demo" primary, "Read docs" secondary), and a hero visual: an abstract 3D-ish graph network of nodes (question / answer / note / tag) connected by glowing edges, hovering above a dark surface.
3. **Trust / how it works bar** — short 3-step pipeline: `Ingest → Extract → Query` with minimal icons.
4. **Feature grid** — 7 cards:
   - LLM-powered decomposition
   - Obsidian-compatible Markdown
   - Interactive knowledge graph
   - Tag & text search
   - Image & transcript support
   - CLI + library + web demo
   - **Local LLM support / privacy-first** (Ollama, offline, no data leaves your machine)
5. **Local-first / privacy section** — a dedicated block with a shield/lock icon and copy like "Your knowledge stays yours. Run locally with Ollama, or bring your own cloud API key."
6. **Graph showcase** — a wide panel showing a stylized Mermaid/force-directed graph with colored node types (questions in violet, answers in cyan, notes in magenta, tags/people as small orbs), titled "See connections, not chaos".
6. **CLI teaser** — a terminal/code window showing a few commands (`agent_memory ingest ./meeting.vtt`, `agent_memory ask "What did we decide about state management?"`) with syntax highlighting.
7. **Demo screenshot placeholder** — a browser-window frame showing the Flutter web demo UI (dark sidebar, record list, search tab, graph tab).
8. **CTA section** — gradient glow background, headline "Start building agent memory today", buttons for GitHub release and live demo.
9. **Footer** — minimal links and copyright.

## Output requirements

- Single high-resolution web design mockup, **16:9 aspect ratio**.
- Modern, polished, ready-for-Figma reference quality.
- No photo-realistic devices or hands; pure UI/illustration.
- Include enough detail to hand off to a frontend developer.
- The overall composition should feel like a premium 2026 AI-tool landing page.
