#!/usr/bin/env bash
# ==============================================================================
# install.sh - Universal Installer for AI Coding Agents on macOS & Linux
# Tuong thich 100% Bash 3.2 (macOS default) va Bash 4+/5+ / Zsh
# Ho tro: omp, claude-code, opencode, codex-cli, dsh, antigravity-cli, all
# ==============================================================================
set -euo pipefail

TARGET="all"
DRY_RUN=false
SKIP_INSTALL=false
FORCE=false
ENABLE_MEMORIX=false
DISABLE_MEMORIX=false
REPO_URL="https://github.com/thanhpk6120/setup-agent-code.git"
ZIP_URL="https://github.com/thanhpk6120/setup-agent-code/archive/refs/heads/main.zip"

# Bien moi truong linh dong cho thu muc Home (phuc vu test co lap hoan toan)
SETUP_HOME_DIR="${SETUP_HOME_DIR:-$HOME}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target|-t)
      TARGET="${2:-all}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --enable-memorix)
      ENABLE_MEMORIX=true
      shift
      ;;
    --disable-memorix)
      DISABLE_MEMORIX=true
      shift
      ;;
    --help|-h)
      echo "Su dung: ./install.sh [--target <agent|all>] [--dry-run] [--skip-install] [--force] [--enable-memorix]"
      echo "Target hop le: all, omp, claude-code, opencode, codex-cli, dsh, antigravity-cli"
      exit 0
      ;;
    *)
      if [[ "$1" =~ ^(all|omp|claude-code|opencode|codex-cli|dsh|antigravity-cli)$ ]]; then
        TARGET="$1"
      fi
      shift
      ;;
  esac
done

TARGET=$(echo "$TARGET" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
if [[ "$TARGET" == "antigravity" ]]; then TARGET="antigravity-cli"; fi

echo "================================================================"
echo "    SETUP-AGENT-CODE INSTALLER FOR MACOS / LINUX"
echo "    Target: $TARGET | DryRun: $DRY_RUN | Force: $FORCE"
echo "    Home Dir: $SETUP_HOME_DIR"
echo "================================================================"

# ==============================================================================
# 1. MOI TRUONG & DUONG DAN LINH DONG CHO MACOS
# ==============================================================================
OS_TYPE=$(uname -s)
ARCH_TYPE=$(uname -m)

# Setup Homebrew PATH cho Apple Silicon vs Intel
if [[ -d "/opt/homebrew/bin" ]]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
elif [[ -d "/usr/local/bin" ]]; then
  export PATH="/usr/local/bin:$PATH"
fi

# Setup uv tool bin va npm global bin
NPM_BIN=""
if command -v npm &>/dev/null; then
  NPM_BIN="$(npm prefix -g 2>/dev/null || true)/bin"
  if [[ -n "$NPM_BIN" && -d "$NPM_BIN" ]]; then
    export PATH="$NPM_BIN:$PATH"
  fi
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Ham Safe-Trash tren macOS / Linux (tuyet doi khong xoa vinh vien)
safe_trash() {
  local p="$1"
  if [[ ! -e "$p" ]]; then return 0; fi
  if $DRY_RUN; then
    echo "  -> [WhatIf] Safe-Trash: $p"
    return 0
  fi
  if command -v trash &>/dev/null; then
    trash "$p" 2>/dev/null || true
    echo "  -> [Trash] Da chuyen '$p' vao Thung rac qua CLI."
  elif [[ "$OS_TYPE" == "Darwin" ]]; then
    local trash_dir="$HOME/.Trash"
    mkdir -p "$trash_dir"
    local base_name
    base_name=$(basename "$p")
    local dest="$trash_dir/${base_name}.$(date +%s)"
    mv "$p" "$dest" 2>/dev/null || true
    echo "  -> [Trash] Da di chuyen '$p' vao ~/.Trash."
  else
    local trash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
    mkdir -p "$trash_dir"
    mv "$p" "$trash_dir/" 2>/dev/null || true
    echo "  -> [Trash] Da di chuyen '$p' vao Thung rac."
  fi
}

# ==============================================================================
# 2. THU MUC TEMP CO DINH & RESUME .ENV (Tuong thich Bash 3.2)
# ==============================================================================
TEMP_BASE="${TMPDIR:-/tmp}/setup-agent-code"
REPO_DIR="$TEMP_BASE/repo"
RESUME_ENV_FILE="$TEMP_BASE/.env"
if ! $DRY_RUN; then mkdir -p "$TEMP_BASE"; fi

# Tim source repo hien tai
CURRENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MONO_ROOT=""
if [[ -f "$CURRENT_SCRIPT_DIR/setup-omp/bootstrap.ps1" || -f "$CURRENT_SCRIPT_DIR/install.ps1" ]]; then
  MONO_ROOT="$CURRENT_SCRIPT_DIR"
  echo "==> Dung ma nguon local: $MONO_ROOT"
else
  # Clone hoac update repo ve thu muc temp co dinh
  if command -v git &>/dev/null; then
    if [[ -d "$REPO_DIR/.git" ]]; then
      echo "==> Thu muc temp co dinh da ton tai: $REPO_DIR. Cap nhat ma nguon (git pull)..."
      git -C "$REPO_DIR" fetch --quiet 2>/dev/null || true
      git -C "$REPO_DIR" checkout main --quiet 2>/dev/null || true
      git -C "$REPO_DIR" pull --quiet 2>/dev/null || true
      MONO_ROOT="$REPO_DIR"
    else
      echo "==> Clone repo ve thu muc temp co dinh: $REPO_DIR..."
      if git clone --depth 1 "$REPO_URL" "$REPO_DIR" --quiet 2>/dev/null; then
        MONO_ROOT="$REPO_DIR"
      fi
    fi
  fi
  if [[ -z "$MONO_ROOT" ]]; then
    echo "==> Tai ma nguon monorepo qua ZIP ve thu muc temp co dinh..."
    ZIP_FILE="$TEMP_BASE/repo.zip"
    curl -fsSL "$ZIP_URL" -o "$ZIP_FILE"
    unzip -q -o "$ZIP_FILE" -d "$TEMP_BASE"
    rm -f "$ZIP_FILE"
    MONO_ROOT=$(find "$TEMP_BASE" -maxdepth 2 -name "setup-agent-code-*" -type d | head -n 1)
    if [[ -z "$MONO_ROOT" ]]; then MONO_ROOT="$TEMP_BASE"; fi
  fi
fi

# Ham doc bien tu file .env (Tuong thich 100% Bash 3.2, khong can declare -A)
get_saved_var() {
  local k="$1"
  local f="${2:-$SAVED_ENV_PATH}"
  if [[ -z "$f" || ! -f "$f" ]]; then return 1; fi
  local line
  line=$(grep -E "^[[:space:]]*${k}[[:space:]]*=" "$f" 2>/dev/null | tail -n 1 || true)
  if [[ -n "$line" ]]; then
    echo "$line" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//'
    return 0
  fi
  return 1
}

# Load va hoi resume .env neu da co
REUSE_ACCEPTED=false
SAVED_ENV_PATH=""

if [[ -f "$MONO_ROOT/.env" ]]; then
  SAVED_ENV_PATH="$MONO_ROOT/.env"
elif [[ -f "$RESUME_ENV_FILE" ]]; then
  SAVED_ENV_PATH="$RESUME_ENV_FILE"
fi

if [[ -n "$SAVED_ENV_PATH" && -f "$SAVED_ENV_PATH" ]]; then
  has_vars=$(grep -E '^[A-Z0-9_]+=' "$SAVED_ENV_PATH" 2>/dev/null | head -n 1 || true)
  if [[ -n "$has_vars" ]]; then
    echo ""
    echo "================================================================"
    echo " [?] PHAT HIEN CAU HINH TU LAN CHAY TRUOC ($SAVED_ENV_PATH)"
    echo "================================================================"
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      if [[ -n "$line" && ! "$line" =~ ^# && "$line" =~ = ]]; then
        k=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
        v=$(echo "$line" | cut -d'=' -f2-)
        disp="$v"
        if [[ "$k" =~ KEY|TOKEN|SECRET|PASSWORD ]]; then disp="***"; fi
        echo "  -> $k = $disp"
      fi
    done < "$SAVED_ENV_PATH"
    echo "================================================================"

    if [[ ! -t 0 ]] || [[ -n "${CI:-}" ]]; then
      echo "  -> [Non-Interactive] Tu dong su dung lai cau hinh truoc do."
      REUSE_ACCEPTED=true
    else
      read -r -p "[?] Ban co muon su dung lai cac bien da nhap khong? (Chi hoi nhung cai chua co) [Y/n]: " ans_reuse
      if [[ -z "$ans_reuse" || "$ans_reuse" =~ ^[Yy] ]]; then
        REUSE_ACCEPTED=true
        echo "  -> [OK] Da nap cau hinh cu. Script se CHI HOI nhung bien chua co."
      else
        REUSE_ACCEPTED=false
        echo "  -> Nguoi dung chon nhap moi tu dau."
      fi
    fi

    if $REUSE_ACCEPTED; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        if [[ -n "$line" && ! "$line" =~ ^# && "$line" =~ = ]]; then
          k=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
          v=$(echo "$line" | cut -d'=' -f2- | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')
          if [[ -n "$k" && -z "${!k:-}" ]]; then
            export "$k=$v"
          fi
        fi
      done < "$SAVED_ENV_PATH"
    fi
  fi
fi

# Ham luu key vao file resume
save_resume_key() {
  local k="$1"
  local v="$2"
  if $DRY_RUN; then return 0; fi
  if [[ -n "${CI:-}" && "${SETUP_ENABLE_RESUME:-}" != "1" ]]; then return 0; fi
  mkdir -p "$TEMP_BASE"
  touch "$RESUME_ENV_FILE"
  if grep -q "^${k}=" "$RESUME_ENV_FILE" 2>/dev/null; then
    local tmp_f="$RESUME_ENV_FILE.tmp"
    grep -v "^${k}=" "$RESUME_ENV_FILE" > "$tmp_f" || true
    echo "${k}=${v}" >> "$tmp_f"
    mv "$tmp_f" "$RESUME_ENV_FILE"
  else
    echo "${k}=${v}" >> "$RESUME_ENV_FILE"
  fi
}

# Ham nhap lieu thong minh (chi prompt khi chua co)
get_env_or_prompt() {
  local env_name="$1"
  local prompt_label="$2"
  local default_val="${3:-}"
  local allow_empty="${4:-false}"

  local current_val="${!env_name:-}"
  if [[ -n "$current_val" ]]; then
    local disp="$current_val"
    if [[ "$env_name" =~ KEY|TOKEN|SECRET|PASSWORD ]]; then disp="***"; fi
    echo "  -> [Reuse] Su dung lai $env_name = $disp"
    return 0
  fi

  if [[ ! -t 0 ]] || [[ -n "${CI:-}" ]]; then
    if [[ -n "$default_val" ]]; then
      export "$env_name=$default_val"
      save_resume_key "$env_name" "$default_val"
      return 0
    elif [[ "$allow_empty" == "true" ]]; then
      export "$env_name="
      return 0
    else
      if $DRY_RUN; then
        export "$env_name=dryrun-placeholder-$env_name"
        return 0
      fi
      echo "Loi: $env_name la bat buoc nhung dang chay non-interactive khong co default." >&2
      exit 1
    fi
  fi

  local prompt_str="[?] $prompt_label"
  if [[ -n "$default_val" ]]; then prompt_str="$prompt_str [$default_val]"; fi
  prompt_str="$prompt_str: "

  while true; do
    read -r -p "$prompt_str" user_in
    if [[ -z "$user_in" ]]; then
      if [[ -n "$default_val" ]]; then
        export "$env_name=$default_val"
        save_resume_key "$env_name" "$default_val"
        return 0
      elif [[ "$allow_empty" == "true" ]]; then
        export "$env_name="
        return 0
      fi
      echo "Truong nay khong duoc de trong. Vui long nhap lai."
      continue
    fi
    export "$env_name=$user_in"
    save_resume_key "$env_name" "$user_in"
    return 0
  done
}

# Ham confirm MCP (Tuong thich Bash 3.2)
confirm_mcp() {
  local name="$1"
  if $FORCE; then return 0; fi
  if $DRY_RUN; then return 1; fi

  local mcp_key="SETUP_MCP_$(echo "$name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
  if $REUSE_ACCEPTED; then
    local saved=""
    if saved=$(get_saved_var "$mcp_key"); then
      if [[ "$saved" == "true" || "$saved" == "1" ]]; then
        echo "  -> [Reuse] Su dung lai lua chon MCP '$name': CO"
        return 0
      else
        echo "  -> [Reuse] Su dung lai lua chon MCP '$name': KHONG"
        return 1
      fi
    fi
  fi

  if [[ ! -t 0 ]] || [[ -n "${CI:-}" ]]; then return 1; fi

  read -r -p "[?] Cai dat MCP '$name'? [y/N]: " choice
  if [[ "$choice" =~ ^[Yy] ]]; then
    save_resume_key "$mcp_key" "true"
    return 0
  else
    save_resume_key "$mcp_key" "false"
    return 1
  fi
}

# Auto-Fix Helper
invoke_auto_fix() {
  local issue="$1"
  local action_desc="$2"
  local fix_cmd="$3"

  if $DRY_RUN || $SKIP_INSTALL || $FORCE; then return 1; fi
  if [[ (! -t 0 || -n "${CI:-}") && "${SETUP_TEST_AUTOFIX:-}" != "1" ]]; then return 1; fi

  echo ""
  echo "================================================================"
  echo " [!] PHAT HIEN SU CO CO THE TU DONG SUA LOI (AUTO-FIX)"
  echo " Su co: $issue"
  echo " De xuat can thiep: $action_desc"
  echo "================================================================"

  read -r -p "[?] Ban co cho phep script tu can thiep sua loi ($action_desc) khong? [Y/n]: " ans_fix
  if [[ -z "$ans_fix" || "$ans_fix" =~ ^[Yy] ]]; then
    echo "  -> Dang thuc hien can thiep..."
    eval "$fix_cmd" && { echo "  -> [OK] Can thiep thanh cong!"; return 0; } || { echo "  -> [!] Can thiep that bai!"; return 1; }
  fi
  return 1
}

# Wait User Intervention Helper
wait_user_intervention() {
  local err_msg="$1"
  local instructions="$2"
  local recheck_cmd="${3:-}"

  if $DRY_RUN || $SKIP_INSTALL || $FORCE; then return 0; fi
  if [[ (! -t 0 || -n "${CI:-}") && "${SETUP_TEST_AUTOFIX:-}" != "1" ]]; then return 1; fi

  echo ""
  echo "================================================================"
  echo " [!] PHAT HIEN SU CO CAN NGUOI DUNG CAN THIEP"
  echo " Chi tiet: $err_msg"
  echo ""
  echo " HUONG DAN XU LY:"
  echo " $instructions"
  echo "================================================================"

  while true; do
    read -r -p "[?] Sau khi ban da xu ly xong, nhan [Enter] de tiep tuc hoac [c] de huy: " ans_wait
    if [[ "$ans_wait" == "c" || "$ans_wait" == "C" ]]; then
      echo "Nguoi dung da huy."
      return 1
    fi
    if [[ -n "$recheck_cmd" ]]; then
      echo "  -> Dang kiem tra lai..."
      if eval "$recheck_cmd"; then
        echo "  -> [OK] Kiem tra lai thanh cong! Tiep tuc..."
        return 0
      else
        echo "  -> [!] Dieu kien van chua dat. Vui long lam theo huong dan tren."
      fi
    else
      return 0
    fi
  done
}

# ==============================================================================
# 3. THU THAP CAU HINH BAN DAU
# ==============================================================================
echo "==> [Giai doan 1/4] Thu thap thong tin cau hinh..."
get_env_or_prompt "AI_BASE_URL" "AI Base URL (Router / Gateway)" "http://localhost:20128/v1" "false"
get_env_or_prompt "AI_API_KEY" "AI API Key" "" "false"

INSTALL_ATLASSIAN=false
INSTALL_GITNEXUS=false
INSTALL_CONTEXT7=false
INSTALL_GLAB=false
INSTALL_CLOAKBROWSER=false
INSTALL_MEMORIX=false
INSTALL_AGENCY=false

if confirm_mcp "company-atlassian"; then INSTALL_ATLASSIAN=true; fi
if confirm_mcp "gitnexus"; then INSTALL_GITNEXUS=true; fi
if confirm_mcp "context7"; then INSTALL_CONTEXT7=true; fi
if confirm_mcp "glab"; then INSTALL_GLAB=true; fi
if confirm_mcp "cloakbrowser"; then INSTALL_CLOAKBROWSER=true; fi
if confirm_mcp "memorix"; then INSTALL_MEMORIX=true; fi
if confirm_mcp "agency"; then INSTALL_AGENCY=true; fi

if $INSTALL_ATLASSIAN; then
  get_env_or_prompt "JIRA_URL" "Jira URL" "https://jira.cybertech.vn" "false"
  get_env_or_prompt "JIRA_PERSONAL_TOKEN" "Jira Personal Token" "YOUR_JIRA_PERSONAL_TOKEN" "false"
  get_env_or_prompt "CONFLUENCE_URL" "Confluence URL" "https://conf.cybertech.vn" "false"
  get_env_or_prompt "CONFLUENCE_PERSONAL_TOKEN" "Confluence Personal Token" "YOUR_CONFLUENCE_PERSONAL_TOKEN" "false"
fi

if $INSTALL_CONTEXT7; then
  get_env_or_prompt "CONTEXT7_API_KEY" "Context7 API Key" "" "true"
fi

if $INSTALL_GLAB; then
  get_env_or_prompt "GITLAB_HOST" "GitLab Host" "10.30.1.17" "false"
  get_env_or_prompt "GITLAB_TOKEN" "GitLab Personal Token" "" "true"
fi

# ==============================================================================
# 4. KIEM TRA MOI TRUONG TIEN QUYET
# ==============================================================================
echo "==> [Giai doan 2/4] Kiem tra moi truong tien quyet..."

check_node() {
  if ! command -v node &>/dev/null; then
    invoke_auto_fix "Chua tim thay Node.js" "Cai dat Node.js qua Homebrew" "brew install node" || \
    wait_user_intervention "Chua co Node.js" "Vui long cai dat Node.js (>= 22.18.0) qua Homebrew: brew install node" "command -v node &>/dev/null"
  fi
  local n_ver
  n_ver=$(node -v 2>/dev/null | tr -d 'v' || true)
  echo "  -> Node.js version: $n_ver"
}
if ! $DRY_RUN && ! $SKIP_INSTALL; then
  check_node
fi

# ==============================================================================
# 5. CAI DAT MCP SERVERS
# ==============================================================================
echo "==> [Giai doan 3/4] Cai dat cac MCP Server da chon..."

if $INSTALL_ATLASSIAN && ! $SKIP_INSTALL && ! $DRY_RUN; then
  echo "==> Cai dat mcp-atlassian qua uv tool..."
  if ! command -v uv &>/dev/null; then
    echo "  -> Chua tim thay uv. Dang cai dat uv..."
    curl -fsSL https://astral.sh/uv/install.sh | bash || true
    export PATH="$HOME/.local/bin:$PATH"
  fi
  if command -v uv &>/dev/null; then
    uv tool install mcp-atlassian==0.23.1 --upgrade || true
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

if $INSTALL_GITNEXUS && ! $SKIP_INSTALL && ! $DRY_RUN; then
  echo "==> Cai dat gitnexus globally..."
  npm install -g gitnexus --silent || true
fi

if $INSTALL_CONTEXT7 && ! $SKIP_INSTALL && ! $DRY_RUN; then
  echo "==> Cai dat @upstash/context7-mcp globally..."
  npm install -g @upstash/context7-mcp --silent || true
fi

if $INSTALL_GLAB && ! $SKIP_INSTALL && ! $DRY_RUN; then
  echo "==> Cai dat glab CLI..."
  if command -v brew &>/dev/null; then
    brew install glab 2>/dev/null || true
  fi
fi

if $INSTALL_MEMORIX && ! $SKIP_INSTALL && ! $DRY_RUN; then
  echo "==> Cai dat memorix globally..."
  npm install -g memorix --silent || true
fi

if $INSTALL_AGENCY && ! $SKIP_INSTALL && ! $DRY_RUN; then
  echo "==> Cai dat agency-mcp-server globally..."
  npm install -g agency-mcp-server --silent || true
fi

# ==============================================================================
# HELPER: TEMPLATE RENDERING & DOC COPY
# ==============================================================================
render_template() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$src" ]]; then return 0; fi

  local gn_path
  gn_path=$(command -v gitnexus 2>/dev/null || echo "gitnexus")
  local agency_path
  agency_path=$(command -v agency-mcp-server 2>/dev/null || echo "agency-mcp-server")
  local ctx_path=""
  if command -v npm &>/dev/null; then
    local n_root
    n_root=$(npm root -g 2>/dev/null || true)
    if [[ -n "$n_root" && -f "$n_root/@upstash/context7-mcp/dist/index.js" ]]; then
      ctx_path="$n_root/@upstash/context7-mcp/dist/index.js"
    fi
  fi
  if [[ -z "$ctx_path" ]]; then ctx_path="node_modules/@upstash/context7-mcp/dist/index.js"; fi
  local cb_path="$SETUP_HOME_DIR/mcp-servers/cloakbrowser/index.js"
  local agy_m="${AGY_MODEL:-gemini-2.5-pro}"

  mkdir -p "$(dirname "$dest")"
  sed \
    -e "s|__AI_BASE_URL__|$AI_BASE_URL|g" \
    -e "s|__AI_API_KEY__|$AI_API_KEY|g" \
    -e "s|__JIRA_URL__|${JIRA_URL:-https://jira.cybertech.vn}|g" \
    -e "s|__JIRA_PERSONAL_TOKEN__|${JIRA_PERSONAL_TOKEN:-YOUR_JIRA_PERSONAL_TOKEN}|g" \
    -e "s|__CONFLUENCE_URL__|${CONFLUENCE_URL:-https://conf.cybertech.vn}|g" \
    -e "s|__CONFLUENCE_PERSONAL_TOKEN__|${CONFLUENCE_PERSONAL_TOKEN:-YOUR_CONFLUENCE_PERSONAL_TOKEN}|g" \
    -e "s|__CONTEXT7_API_KEY__|${CONTEXT7_API_KEY:-}|g" \
    -e "s|__GITLAB_HOST__|${GITLAB_HOST:-10.30.1.17}|g" \
    -e "s|__GITLAB_TOKEN__|${GITLAB_TOKEN:-}|g" \
    -e "s|__GITNEXUS_PATH__|$gn_path|g" \
    -e "s|__AGENCY_PATH__|$agency_path|g" \
    -e "s|__CONTEXT7_PATH__|$ctx_path|g" \
    -e "s|__CLOAKBROWSER_SCRIPT__|$cb_path|g" \
    -e "s|__AGY_MODEL__|$agy_m|g" \
    -e 's|"cmd", "/c", ||g' \
    -e 's|"cmd"|"bash"|g' \
    -e 's|"/c", ||g' \
    -e 's|\.cmd"|"|g' \
    -e 's|cmd = "cmd"|cmd = "bash"|g' \
    -e 's|args = \["/c", |args = \[|g' \
    "$src" > "$dest"
}

copy_doc() {
  local agent_dir="$1"
  local doc_name="$2"
  local dest_dir="$3"
  local dest_name="${4:-$doc_name}"
  mkdir -p "$dest_dir"
  if [[ -f "$MONO_ROOT/$agent_dir/templates/$doc_name" ]]; then
    cp -f "$MONO_ROOT/$agent_dir/templates/$doc_name" "$dest_dir/$dest_name"
  elif [[ -f "$MONO_ROOT/$agent_dir/$doc_name" ]]; then
    cp -f "$MONO_ROOT/$agent_dir/$doc_name" "$dest_dir/$dest_name"
  fi
}

sync_skills() {
  local target_skills_dir="$1"
  local src_skills="$MONO_ROOT/setup-omp/skills"
  if [[ ! -d "$src_skills" ]]; then return 0; fi
  if $DRY_RUN; then
    echo "  -> [WhatIf] Sao chep skills sang: $target_skills_dir"
    return 0
  fi
  mkdir -p "$target_skills_dir"
  for s_dir in "$src_skills"/*; do
    if [[ -d "$s_dir" ]]; then
      local b_name
      b_name=$(basename "$s_dir")
      if ! $ENABLE_MEMORIX && [[ "$b_name" =~ ^memorix- ]]; then
        continue
      fi
      cp -Rf "$s_dir" "$target_skills_dir/"
    fi
  done
  echo "  -> [OK] Dong bo skills sang $target_skills_dir thanh cong."
}

# ==============================================================================
# 6. TRIEN KHAI TUNG AGENT TARGET TREN MACOS
# ==============================================================================
echo "==> [Giai doan 4/4] Trien khai cac Agent target..."

install_claude_code() {
  echo "----------------------------------------------------------------"
  echo "  Trien khai Claude Code tren macOS"
  echo "----------------------------------------------------------------"
  if ! $SKIP_INSTALL && ! $DRY_RUN && ! command -v claude &>/dev/null; then
    echo "==> Cai dat Claude Code CLI..."
    curl -fsSL https://claude.ai/install.sh | bash || npm install -g @anthropic-ai/claude-code || true
  fi
  local claude_dir="$SETUP_HOME_DIR/.claude"
  if ! $DRY_RUN; then
    mkdir -p "$claude_dir" "$claude_dir/hud" "$SETUP_HOME_DIR/.trash-guard"
    
    # 1. CLAUDE.md
    copy_doc "setup-claude-code" "CLAUDE.md" "$claude_dir"

    # 2. .claude.json
    local claude_json="$SETUP_HOME_DIR/.claude.json"
    render_template "$MONO_ROOT/setup-claude-code/templates/claude.json" "$claude_json"

    # 3. settings.json
    local settings_json="$claude_dir/settings.json"
    render_template "$MONO_ROOT/setup-claude-code/templates/settings.json" "$settings_json"

    # 4. Trash Guard Hook
    if [[ -d "$MONO_ROOT/setup-claude-code/trash-guard" ]]; then
      cp -Rf "$MONO_ROOT/setup-claude-code/trash-guard"/* "$SETUP_HOME_DIR/.trash-guard/" 2>/dev/null || true
      chmod +x "$SETUP_HOME_DIR/.trash-guard"/*.sh 2>/dev/null || true
    fi

    # 5. Skills
    sync_skills "$claude_dir/skills"
  else
    echo "  -> [WhatIf] Cau hinh Claude Code tai $claude_dir"
  fi
  echo "  -> [OK] Claude Code da duoc cau hinh tai $claude_dir"
}

install_omp() {
  echo "----------------------------------------------------------------"
  echo "  Trien khai OMP tren macOS"
  echo "----------------------------------------------------------------"
  if ! $SKIP_INSTALL && ! $DRY_RUN && ! command -v omp &>/dev/null; then
    echo "==> Cai dat OMP CLI..."
    curl -fsSL https://omp.sh/install | sh || true
  fi
  local omp_dir="$SETUP_HOME_DIR/.omp/agent"
  if ! $DRY_RUN; then
    mkdir -p "$omp_dir" "$SETUP_HOME_DIR/.omp/extensions"
    
    copy_doc "setup-omp" "AGENTS.md" "$omp_dir"
    copy_doc "setup-omp" "RULES.md" "$omp_dir"
    copy_doc "setup-omp" "SYSTEM.md" "$omp_dir"

    # config.yml
    render_template "$MONO_ROOT/setup-omp/templates/config.yml" "$omp_dir/config.yml"
    sed -i '' 's|shellPath: .*|shellPath: "/bin/zsh"|g' "$omp_dir/config.yml" 2>/dev/null || sed -i 's|shellPath: .*|shellPath: "/bin/zsh"|g' "$omp_dir/config.yml" 2>/dev/null || true

    # models.yml & mcp.json
    render_template "$MONO_ROOT/setup-omp/templates/models.yml" "$omp_dir/models.yml"
    render_template "$MONO_ROOT/setup-omp/templates/mcp.json" "$omp_dir/mcp.json"

    # Extension Trash Guard
    if [[ -f "$MONO_ROOT/setup-omp/extensions/no-hard-delete.ts" ]]; then
      cp -f "$MONO_ROOT/setup-omp/extensions/no-hard-delete.ts" "$SETUP_HOME_DIR/.omp/extensions/no-hard-delete.ts"
    fi

    # Skills
    sync_skills "$omp_dir/skills"
  else
    echo "  -> [WhatIf] Cau hinh OMP tai $omp_dir"
  fi
  echo "  -> [OK] OMP da duoc cau hinh tai $omp_dir"
}

install_opencode() {
  echo "----------------------------------------------------------------"
  echo "  Trien khai OpenCode tren macOS"
  echo "----------------------------------------------------------------"
  if ! $SKIP_INSTALL && ! $DRY_RUN && ! command -v opencode &>/dev/null; then
    echo "==> Cai dat OpenCode CLI..."
    npm install -g opencode-ai 2>/dev/null || true
  fi
  local oc_dir="$SETUP_HOME_DIR/.config/opencode"
  if ! $DRY_RUN; then
    mkdir -p "$oc_dir/plugins" "$oc_dir/hooks"
    copy_doc "setup-opencode" "AGENTS.md" "$oc_dir"
    render_template "$MONO_ROOT/setup-opencode/templates/opencode.json" "$oc_dir/opencode.json"

    # Plugins no-hard-delete
    if [[ -d "$MONO_ROOT/setup-opencode/templates/plugins" ]]; then
      cp -Rf "$MONO_ROOT/setup-opencode/templates/plugins"/* "$oc_dir/plugins/" 2>/dev/null || true
    fi

    sync_skills "$oc_dir/skills"
  else
    echo "  -> [WhatIf] Cau hinh OpenCode tai $oc_dir"
  fi
  echo "  -> [OK] OpenCode da duoc cau hinh tai $oc_dir"
}

install_codex_cli() {
  echo "----------------------------------------------------------------"
  echo "  Trien khai Codex CLI tren macOS"
  echo "----------------------------------------------------------------"
  if ! $SKIP_INSTALL && ! $DRY_RUN && ! command -v codex &>/dev/null; then
    echo "==> Cai dat Codex CLI..."
    npm install -g @openai/codex 2>/dev/null || true
  fi
  local codex_dir="$SETUP_HOME_DIR/.codex"
  if ! $DRY_RUN; then
    mkdir -p "$codex_dir"
    copy_doc "setup-codex-cli" "AGENTS.md" "$codex_dir"
    copy_doc "setup-codex-cli" "AGENTS.md" "$codex_dir" "CODEX.md"
    render_template "$MONO_ROOT/setup-codex-cli/templates/config.toml" "$codex_dir/config.toml"
    sync_skills "$codex_dir/skills"
  else
    echo "  -> [WhatIf] Cau hinh Codex CLI tai $codex_dir"
  fi
  echo "  -> [OK] Codex CLI da duoc cau hinh tai $codex_dir"
}

install_dsh() {
  echo "----------------------------------------------------------------"
  echo "  Trien khai DSH tren macOS"
  echo "----------------------------------------------------------------"
  if ! $SKIP_INSTALL && ! $DRY_RUN && ! command -v dsh &>/dev/null; then
    echo "==> Cai dat DSH CLI..."
    npm install -g @deepseek-ai/dsh 2>/dev/null || true
  fi
  local dsh_home="$SETUP_HOME_DIR/.dsh"
  local dsh_profile="$SETUP_HOME_DIR/Library/Application Support/dsh-desktop/harness/profiles/web"
  if [[ "$OS_TYPE" != "Darwin" ]]; then
    dsh_profile="$SETUP_HOME_DIR/.config/dsh-desktop/harness/profiles/web"
  fi

  if ! $DRY_RUN; then
    mkdir -p "$dsh_home" "$dsh_profile"
    copy_doc "setup-dsh" "AGENTS.md" "$dsh_home"
    
    # cordis.patch.yml
    render_template "$MONO_ROOT/setup-dsh/templates/cordis.patch.yml" "$dsh_profile/cordis.patch.yml"
    local ctx_path=""
    if command -v npm &>/dev/null; then
      local n_root
      n_root=$(npm root -g 2>/dev/null || true)
      if [[ -n "$n_root" && -f "$n_root/@upstash/context7-mcp/dist/index.js" ]]; then
        ctx_path="$n_root/@upstash/context7-mcp/dist/index.js"
      fi
    fi
    if [[ -z "$ctx_path" ]]; then ctx_path="node_modules/@upstash/context7-mcp/dist/index.js"; fi
    sed -i '' \
      -e "s|__MEMORIX_CONFIG__|    command: memorix\\"$'\n'"    args:\\"$'\n'"      - mcp|g" \
      -e "s|__GITNEXUS_CONFIG__|    command: gitnexus\\"$'\n'"    args:\\"$'\n'"      - mcp|g" \
      -e "s|__CONTEXT7_CONFIG__|    command: node\\"$'\n'"    args:\\"$'\n'"      - $ctx_path|g" \
      "$dsh_profile/cordis.patch.yml" 2>/dev/null || sed -i \
      -e "s|__MEMORIX_CONFIG__|    command: memorix\n    args:\n      - mcp|g" \
      -e "s|__GITNEXUS_CONFIG__|    command: gitnexus\n    args:\n      - mcp|g" \
      -e "s|__CONTEXT7_CONFIG__|    command: node\n    args:\n      - $ctx_path|g" \
      "$dsh_profile/cordis.patch.yml" 2>/dev/null || true

    # .credentials.yaml
    local creds_file
    creds_file="$(dirname "$(dirname "$dsh_profile")")/.credentials.yaml"
    mkdir -p "$(dirname "$creds_file")"
    cat <<EOF > "$creds_file"
Refs:
  ANTHROPIC_API_KEY: "$AI_API_KEY"
EOF

    sync_skills "$dsh_home/skills"
  else
    echo "  -> [WhatIf] Cau hinh DSH tai $dsh_home va $dsh_profile"
  fi
  echo "  -> [OK] DSH da duoc cau hinh tai $dsh_home"
}

install_antigravity_cli() {
  echo "----------------------------------------------------------------"
  echo "  Trien khai Antigravity CLI tren macOS"
  echo "----------------------------------------------------------------"
  local agy_dir="$SETUP_HOME_DIR/.gemini/antigravity-cli"
  local agy_user_dir="$SETUP_HOME_DIR/Library/Application Support/Antigravity/User"
  if [[ "$OS_TYPE" != "Darwin" ]]; then
    agy_user_dir="$SETUP_HOME_DIR/.config/Antigravity/User"
  fi

  if ! $DRY_RUN; then
    mkdir -p "$agy_dir/hooks" "$agy_user_dir"
    copy_doc "setup-antigravity-cli" "AGENTS.md" "$agy_dir"
    render_template "$MONO_ROOT/setup-antigravity-cli/templates/settings.json" "$agy_dir/settings.json"

    # keybindings.json
    if [[ -f "$MONO_ROOT/setup-antigravity-cli/templates/keybindings.json" ]]; then
      cp -f "$MONO_ROOT/setup-antigravity-cli/templates/keybindings.json" "$agy_dir/keybindings.json"
      cp -f "$MONO_ROOT/setup-antigravity-cli/templates/keybindings.json" "$agy_user_dir/keybindings.json" 2>/dev/null || true
    fi

    sync_skills "$agy_dir/skills"
  else
    echo "  -> [WhatIf] Cau hinh Antigravity CLI tai $agy_dir"
  fi
  echo "  -> [OK] Antigravity CLI da duoc cau hinh tai $agy_dir"
}

# Dispatch
case "$TARGET" in
  all)
    install_omp
    install_claude_code
    install_opencode
    install_codex_cli
    install_dsh
    install_antigravity_cli
    ;;
  omp) install_omp ;;
  claude-code) install_claude_code ;;
  opencode) install_opencode ;;
  codex-cli) install_codex_cli ;;
  dsh) install_dsh ;;
  antigravity-cli) install_antigravity_cli ;;
  *)
    echo "Target khong hop le: $TARGET" >&2
    exit 1
    ;;
esac

echo ""
echo "================================================================"
echo " [OK] CAI DAT VA THIET LAP HOAN TAT CHO TARGET: $TARGET!"
echo " Cau hinh resume da duoc luu tai: $RESUME_ENV_FILE"
echo "================================================================"
