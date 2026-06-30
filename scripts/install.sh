#!/bin/bash
# flutter_agent_memory CLI installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/IstiN/flutter_agent_memory/main/install | bash
#   FAM_INSTALL_DIR=/opt/fam bash scripts/install.sh
#   FAM_REPO_DIR=/path/to/local/repo bash scripts/install.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO="IstiN/flutter_agent_memory"
INSTALL_DIR="${FAM_INSTALL_DIR:-$HOME/.flutter_agent_memory}"
INTERNAL_BIN_DIR="$INSTALL_DIR/bin"
DART_SDK_DIR="$INSTALL_DIR/dart-sdk"
REPO_DIR="$INSTALL_DIR/repo"
BINARY_PATH="$INTERNAL_BIN_DIR/agent_memory-bin"

DART_VERSION="${FAM_DART_VERSION:-3.12.2}"

info() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
progress() { echo -e "${BLUE}$1${NC}"; }

# Pick a directory that is already on PATH and user-writable.
# Prefer $FAM_BIN_DIR, then ~/.local/bin, then ~/bin, then the install dir/bin.
detect_bin_dir() {
  if [ -n "${FAM_BIN_DIR:-}" ]; then
    echo "$FAM_BIN_DIR"
    return 0
  fi

  local candidates=("$HOME/.local/bin" "$HOME/bin")
  for dir in "${candidates[@]}"; do
    if [[ ":$PATH:" == *":$dir:"* ]]; then
      echo "$dir"
      return 0
    fi
  done

  echo "$INTERNAL_BIN_DIR"
}

BIN_DIR=$(detect_bin_dir)
WRAPPER_PATH="$BIN_DIR/agent_memory"

detect_os() {
  case "$(uname -s)" in
    Linux*)     echo "linux";;
    Darwin*)    echo "macos";;
    CYGWIN*|MINGW*|MSYS*) echo "windows";;
    *)          error "Unsupported OS: $(uname -s)";;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64";;
    arm64|aarch64) echo "arm64";;
    *)            error "Unsupported architecture: $(uname -m)";;
  esac
}

OS=$(detect_os)
ARCH=$(detect_arch)

ensure_dart() {
  if command -v dart >/dev/null 2>&1; then
    info "Using system Dart: $(dart --version 2>&1 | head -n 1)"
    DART_CMD="dart"
    return 0
  fi

  if [ -x "$DART_SDK_DIR/bin/dart" ]; then
    info "Using bundled Dart from $DART_SDK_DIR"
    DART_CMD="$DART_SDK_DIR/bin/dart"
    export PATH="$DART_SDK_DIR/bin:$PATH"
    return 0
  fi

  progress "Dart not found. Downloading Dart SDK $DART_VERSION for $OS-$ARCH..."
  mkdir -p "$DART_SDK_DIR"

  local archive="dartsdk-$OS-$ARCH-release.zip"
  local url="https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/$archive"
  local tmp_archive="$INSTALL_DIR/$archive"

  curl -fsSL "$url" -o "$tmp_archive" || error "Failed to download Dart SDK from $url"
  unzip -q "$tmp_archive" -d "$INSTALL_DIR" || error "Failed to extract Dart SDK"
  mv "$INSTALL_DIR/dart-sdk"/* "$DART_SDK_DIR/" 2>/dev/null || true
  rm -f "$tmp_archive"

  DART_CMD="$DART_SDK_DIR/bin/dart"
  export PATH="$DART_SDK_DIR/bin:$PATH"
  info "Dart installed: $($DART_CMD --version 2>&1 | head -n 1)"
}

install_repo() {
  mkdir -p "$INSTALL_DIR"

  if [ -n "${FAM_REPO_DIR:-}" ]; then
    progress "Using local repository from $FAM_REPO_DIR..."
    rm -rf "$REPO_DIR"
    cp -R "$FAM_REPO_DIR" "$REPO_DIR"
    return 0
  fi

  if [ -d "$REPO_DIR/.git" ]; then
    progress "Updating existing repository..."
    (cd "$REPO_DIR" && git pull --rebase) || warn "Could not update repository; using current version"
  else
    progress "Cloning $REPO..."
    rm -rf "$REPO_DIR"
    git clone --depth 1 "https://github.com/$REPO.git" "$REPO_DIR" || error "Failed to clone repository"
  fi
}

compile_binary() {
  progress "Installing dependencies..."
  (cd "$REPO_DIR" && "$DART_CMD" pub get) || error "dart pub get failed"

  progress "Compiling native binary..."
  mkdir -p "$INTERNAL_BIN_DIR"
  "$DART_CMD" compile exe "$REPO_DIR/bin/agent_memory.dart" -o "$BINARY_PATH" || error "Compilation failed"
  chmod +x "$BINARY_PATH"
  info "Binary compiled: $BINARY_PATH"
}

create_wrapper() {
  progress "Creating wrapper script..."
  mkdir -p "$BIN_DIR"

  cat > "$WRAPPER_PATH" <<EOF
#!/bin/bash
# flutter_agent_memory wrapper
set -e

# Resolve the real script path in case the command is a symlink.
if command -v realpath >/dev/null 2>&1; then
  SCRIPT_PATH=\$(realpath "\${BASH_SOURCE[0]}")
else
  SCRIPT_PATH=\${BASH_SOURCE[0]}
fi
SCRIPT_DIR="\$(cd "\$(dirname "\$SCRIPT_PATH")" && pwd)"

# Install location is hard-coded at install time so the wrapper can live on PATH.
INSTALL_DIR="$INSTALL_DIR"
DART_SDK_DIR="\$INSTALL_DIR/dart-sdk"
BINARY="\$INSTALL_DIR/bin/agent_memory-bin"

if [ -x "\$DART_SDK_DIR/bin/dart" ]; then
  export PATH="\$DART_SDK_DIR/bin:\$PATH"
fi

if [ -x "\$BINARY" ]; then
  exec "\$BINARY" "\$@"
else
  echo "Error: agent_memory binary not found at \$BINARY" >&2
  echo "Please re-run the installer." >&2
  exit 1
fi
EOF

  chmod +x "$WRAPPER_PATH"
  info "Wrapper installed: $WRAPPER_PATH"
}

update_path() {
  if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
    return 0
  fi

  local shell_rc=""
  case "${SHELL##*/}" in
    zsh) shell_rc="$HOME/.zshrc" ;;
    bash) shell_rc="$HOME/.bashrc" ;;
    *) shell_rc="$HOME/.profile" ;;
  esac

  if [ -f "$shell_rc" ]; then
    if ! grep -q "$BIN_DIR" "$shell_rc" 2>/dev/null; then
      echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$shell_rc"
      info "Added $BIN_DIR to PATH in $shell_rc"
      warn "Run 'source $shell_rc' or restart your terminal to use 'agent_memory'"
    fi
  fi
}

main() {
  info "Installing flutter_agent_memory CLI..."
  ensure_dart
  install_repo
  compile_binary
  create_wrapper
  update_path
  info "Installation complete."
  info "Run: agent_memory --help"
}

main "$@"
