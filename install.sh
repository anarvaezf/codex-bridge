#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_BASE_DIR="."
DEFAULT_INSTALL_FOLDER_NAME="codex-bridge"
DEFAULT_PORT="8787"
DEFAULT_CODEX_TIMEOUT="60000"

# Colors
RESET="\033[0m"
BOLD="\033[1m"

BLUE="\033[34m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
MAGENTA="\033[35m"

MUTED="\033[90m"

print_header() {
  echo ""
  echo -e "${BOLD}${MAGENTA}🚀 Codex Bridge Installer${RESET}"
  echo "This installer creates a fresh codex-bridge runtime installation."
  echo ""
}

print_info() {
  echo -e "${CYAN}ℹ️  $1${RESET}"
}

print_success() {
  echo -e "${GREEN}✅ $1${RESET}"
}

print_warn() {
  echo -e "${YELLOW}⚠️  $1${RESET}"
}

print_error() {
  echo -e "${RED}❌ $1${RESET}"
}

prompt_with_default() {
  local label="$1"
  local default_value="$2"
  local user_input

  printf "%b" "${BLUE}➜ ${label} ${MUTED}(${default_value})${RESET}: " > /dev/tty
  IFS= read -r user_input < /dev/tty || true

  if [[ -z "$user_input" ]]; then
    printf "%s" "$default_value"
  else
    printf "%s" "$user_input"
  fi
}

expand_path() {
  local input_path="$1"

  input_path="${input_path/#\~/$HOME}"

  if [[ "$input_path" != /* ]]; then
    input_path="$(pwd)/$input_path"
  fi

  printf "%s" "$input_path"
}

validate_command() {
  local command_name="$1"
  local human_name="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    print_error "$human_name is not installed."
    exit 1
  fi
}

copy_runtime_files() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  mkdir -p "$target_dir/agents"

  cp "$source_dir/package.json" "$target_dir/package.json"
  cp "$source_dir/package-lock.json" "$target_dir/package-lock.json"
  cp "$source_dir/server.min.js" "$target_dir/server.js"

  rsync -a "$source_dir/agents/" "$target_dir/agents/"
}

print_header

BASE_DIR_INPUT="$(prompt_with_default "Base directory (codex-bridge will be created inside)" "$DEFAULT_BASE_DIR")"
BASE_DIR="$(expand_path "$BASE_DIR_INPUT")"
TARGET_DIR="$BASE_DIR/$DEFAULT_INSTALL_FOLDER_NAME"

DEFAULT_AGENTS_DIR="$TARGET_DIR/agents"
DEFAULT_TEMP_WORKSPACES_DIR="$TARGET_DIR/temp-workspaces"

echo ""
print_info "Source directory: $SOURCE_DIR"
print_info "Base directory: $BASE_DIR"
print_info "Install directory: $TARGET_DIR"

if [[ -e "$TARGET_DIR" ]]; then
  print_error "$TARGET_DIR already exists."
  exit 1
fi

validate_command "node" "Node.js"
validate_command "npm" "npm"
validate_command "codex" "Codex CLI"
validate_command "rsync" "rsync"

if [[ ! -f "$SOURCE_DIR/server.min.js" ]]; then
  print_error "server.min.js was not found."
  echo "Run 'npm run build' before installing."
  exit 1
fi

print_info "Checking Codex login..."
CODEX_STATUS="$(codex login status 2>&1 || true)"

if [[ "$CODEX_STATUS" != *"Logged in"* ]]; then
  print_error "Codex CLI is not logged in."
  echo "Run: codex login"
  echo ""
  echo "codex login status output:"
  echo "$CODEX_STATUS"
  exit 1
fi

mkdir -p "$TARGET_DIR"

print_info "Copying runtime files..."
copy_runtime_files "$SOURCE_DIR" "$TARGET_DIR"

mkdir -p "$TARGET_DIR/temp-workspaces"

echo ""
echo -e "${BOLD}${MAGENTA}⚙️  Configuration${RESET}"
echo "Press Enter to accept the default value for each field."
echo ""

PORT_VALUE="$(prompt_with_default "Port" "$DEFAULT_PORT")"

AGENTS_DIR_INPUT="$(prompt_with_default "Agents directory" "$DEFAULT_AGENTS_DIR")"
AGENTS_DIR_VALUE="$(expand_path "$AGENTS_DIR_INPUT")"

TEMP_WORKSPACES_DIR_INPUT="$(prompt_with_default "Temporary workspaces directory" "$DEFAULT_TEMP_WORKSPACES_DIR")"
TEMP_WORKSPACES_DIR_VALUE="$(expand_path "$TEMP_WORKSPACES_DIR_INPUT")"

TIMEOUT_VALUE="$(prompt_with_default "Timeout in milliseconds" "$DEFAULT_CODEX_TIMEOUT")"

cat > "$TARGET_DIR/.env" <<EOF
PORT=$PORT_VALUE
CODEX_BRIDGE_ROOT=$TARGET_DIR
AGENTS_DIR=$AGENTS_DIR_VALUE
TEMP_WORKSPACES_DIR=$TEMP_WORKSPACES_DIR_VALUE
CODEX_TIMEOUT=$TIMEOUT_VALUE
EOF

mkdir -p "$TEMP_WORKSPACES_DIR_VALUE"

echo ""
print_success ".env created at:"
echo "$TARGET_DIR/.env"

echo ""
print_info "Installing dependencies..."
cd "$TARGET_DIR"
npm install

echo ""
print_success "Installation complete"
echo ""
echo -e "${BOLD}Run:${RESET}"
echo "cd \"$TARGET_DIR\""
echo "npm start"
echo ""
echo -e "${BOLD}URL:${RESET}"
echo "http://localhost:$PORT_VALUE"