#!/bin/bash
# flutter_agent_memory development wrapper
# Usage: ./scripts/agent_memory.sh [command] [args...]
# This wrapper uses the local repository source. The CLI itself loads a .env
# file from the current working directory when present.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find dart command (system, flutter, or bundled install)
find_dart_command() {
  if command -v dart >/dev/null 2>&1; then
    echo "dart"
    return 0
  fi
  if command -v flutter >/dev/null 2>&1; then
    echo "flutter pub run"
    return 0
  fi
  local bundled="$HOME/.flutter_agent_memory/dart-sdk/bin/dart"
  if [ -x "$bundled" ]; then
    echo "$bundled"
    return 0
  fi
  return 1
}

DART_CMD=$(find_dart_command 2>/dev/null) || {
  echo "Error: Dart SDK not found." >&2
  echo "Install it from https://dart.dev/get-dart or run scripts/install.sh" >&2
  exit 1
}

cd "$REPO_DIR"

if [ "$DART_CMD" = "flutter pub run" ]; then
  exec flutter run --target=bin/agent_memory.dart -- "$@"
else
  exec "$DART_CMD" run bin/agent_memory.dart -- "$@"
fi
