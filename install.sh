#!/usr/bin/env bash
# install.sh - macOS/Linux launcher for the setup-agent-code engine.
# All ordering/option logic lives in core/engine.mjs (shared with Windows).
set -euo pipefail

REPO_GIT="https://github.com/thanhpk6120/setup-agent-code.git"
REPO_ZIP="https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip"
ENGINE_ARGS=()
TARGET_SPECIFIED=0
NODE_INSTALL_DISABLED=0
NODE_INSTALL_CONSENT=0

usage() {
  echo "setup-agent-code - cai dat & cau hinh AI coding agents"
  echo "Usage: install.sh [--target all|omp|claude-code|opencode|codex-cli|dsh|antigravity-cli|goose|roo-code] [options]"
  echo "       install.sh --help   (danh sach option day du)"
}

need_value() {
  if [[ $# -lt 2 || "${2:-}" == -* ]]; then
    echo "Option $1 can gia tri." >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target|-t)      need_value "$@"; ENGINE_ARGS+=("--target" "$2"); TARGET_SPECIFIED=1; shift 2 ;;
    --dry-run)        NODE_INSTALL_DISABLED=1; ENGINE_ARGS+=("--dry-run"); shift ;;
    --skip-install)   NODE_INSTALL_DISABLED=1; ENGINE_ARGS+=("--skip-install"); shift ;;
    --force)          NODE_INSTALL_CONSENT=1; ENGINE_ARGS+=("--force"); shift ;;
    --overwrite-all)  ENGINE_ARGS+=("--overwrite-all"); shift ;;
    --memorix|--enable-memorix)   ENGINE_ARGS+=("--memorix"); shift ;;
    --no-memorix|--disable-memorix) ENGINE_ARGS+=("--no-memorix"); shift ;;
    --mcp)            need_value "$@"; ENGINE_ARGS+=("--mcp" "$2"); shift 2 ;;
    --preset)         need_value "$@"; ENGINE_ARGS+=("--preset" "$2"); shift 2 ;;
    --yes|-y)         NODE_INSTALL_CONSENT=1; ENGINE_ARGS+=("--yes"); shift ;;
    --doctor)         NODE_INSTALL_DISABLED=1; ENGINE_ARGS+=("--doctor"); shift ;;
    --json)           ENGINE_ARGS+=("--json"); shift ;;
    --report)         need_value "$@"; ENGINE_ARGS+=("--report" "$2"); shift 2 ;;
    --strict)         ENGINE_ARGS+=("--strict"); shift ;;
    --quiet|-q)       ENGINE_ARGS+=("--quiet"); shift ;;
    --verbose)        ENGINE_ARGS+=("--verbose"); shift ;;
    --env-file)       need_value "$@"; ENGINE_ARGS+=("--env-file" "$2"); shift 2 ;;
    --help|-h)        NODE_INSTALL_DISABLED=1; ENGINE_ARGS+=("--help"); shift ;;
    --version)        NODE_INSTALL_DISABLED=1; ENGINE_ARGS+=("--version"); shift ;;
    all|omp|claude-code|opencode|codex-cli|dsh|antigravity|antigravity-cli|goose|roo|roo-code)
                      ENGINE_ARGS+=("--target" "$1"); TARGET_SPECIFIED=1; shift ;;
    *)
      echo "Option khong hop le: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $TARGET_SPECIFIED -eq 0 && -n "${SETUP_TARGET:-}" ]]; then
  ENGINE_ARGS+=("--target" "$SETUP_TARGET")
fi

# ---- locate repo (local checkout first, otherwise fixed temp clone)
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
fi

is_engine_root() { [[ -n "${1:-}" && -f "$1/core/engine.mjs" ]]; }

ENGINE_ROOT=""
if is_engine_root "${SCRIPT_DIR:-}"; then
  ENGINE_ROOT="$SCRIPT_DIR"
elif is_engine_root "$(pwd)"; then
  ENGINE_ROOT="$(pwd)"
else
  TEMP_BASE="${TMPDIR:-/tmp}/setup-agent-code"
  REPO_DIR="$TEMP_BASE/repo"
  mkdir -p "$TEMP_BASE"
  if command -v git &>/dev/null; then
    if [[ -d "$REPO_DIR/.git" ]]; then
      git -C "$REPO_DIR" fetch --quiet 2>/dev/null || true
      git -C "$REPO_DIR" checkout main --quiet 2>/dev/null || true
      git -C "$REPO_DIR" pull --quiet 2>/dev/null || true
    else
      git clone --depth 1 "$REPO_GIT" "$REPO_DIR" --quiet 2>/dev/null || true
    fi
    if is_engine_root "$REPO_DIR"; then ENGINE_ROOT="$REPO_DIR"; fi
  fi
  if [[ -z "$ENGINE_ROOT" ]]; then
    ZIP_FILE="$TEMP_BASE/repo.zip"
    curl -fsSL "$REPO_ZIP" -o "$ZIP_FILE"
    unzip -q -o "$ZIP_FILE" -d "$TEMP_BASE"
    ENGINE_ROOT="$(find "$TEMP_BASE" -maxdepth 2 -name 'setup-agent-code-*' -type d | head -n 1)"
    # Temp zip: move to trash instead of hard delete.
    if [[ -f "$ZIP_FILE" ]]; then
      if command -v trash &>/dev/null; then trash "$ZIP_FILE" 2>/dev/null || true; fi
    fi
  fi
fi

if [[ -z "$ENGINE_ROOT" || ! -f "$ENGINE_ROOT/core/engine.mjs" ]]; then
  echo "Khong tim thay core/engine.mjs (repo chua duoc tai ve dung)." >&2
  exit 1
fi

# ---- ensure Node.js (engine + most MCP servers need >= 22.18)
if ! command -v node &>/dev/null; then
  if [[ $NODE_INSTALL_DISABLED -eq 1 ]]; then
    echo "Khong tim thay Node.js >= 22.18.0. Che do nay khong tu cai Node.js; cai dat tai https://nodejs.org roi chay lai." >&2
    exit 1
  fi
  if [[ $NODE_INSTALL_CONSENT -eq 0 ]]; then
    if [[ ! -t 0 || ! -t 1 ]]; then
      echo "Khong tu cai Node.js trong che do khong tuong tac. Cai dat tai https://nodejs.org hoac chay lai voi --yes/--force de dong y cai dat." >&2
      exit 1
    fi
    read -r -p "Chua co Node.js. Dong y cai dat Node.js? [y/N] " answer || answer=""
    case "$answer" in
      y|Y|yes|YES|Yes) ;;
      *) echo "Da tu choi cai Node.js. Cai dat tai https://nodejs.org roi chay lai." >&2; exit 1 ;;
    esac
  fi
  echo "==> Chua co Node.js, thu cai dat..."
  if command -v brew &>/dev/null; then
    brew install node || true
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update -y && sudo apt-get install -y nodejs npm || true
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y nodejs || true
  fi
fi
if ! command -v node &>/dev/null; then
  echo "Khong tim thay Node.js >= 22.18.0. Cai dat tai https://nodejs.org roi chay lai." >&2
  exit 1
fi

if [[ ${#ENGINE_ARGS[@]} -gt 0 ]]; then
  exec node "$ENGINE_ROOT/core/engine.mjs" "${ENGINE_ARGS[@]}"
else
  exec node "$ENGINE_ROOT/core/engine.mjs"
fi
