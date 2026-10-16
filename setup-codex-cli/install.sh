#!/usr/bin/env bash
# Wrapper install.sh cho codex-cli
set -euo pipefail

DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
fi

ROOT_INSTALL=""
if [[ -n "$DIR" && -f "$DIR/../install.sh" ]]; then
  ROOT_INSTALL="$DIR/../install.sh"
fi

if [[ -n "$ROOT_INSTALL" && -f "$ROOT_INSTALL" ]]; then
  exec bash "$ROOT_INSTALL" --target "codex-cli" "$@"
else
  # Fallback: khi goi wrapper co lap qua curl / url ma khong co thu muc cha
  INSTALL_URL="https://raw.githubusercontent.com/thanhpk6120/setup-agent-code/main/install.sh"
  echo "==> Khong tim thay install.sh goc tai local, tai va chay truc tiep tu GitHub..."
  exec curl -fsSL "$INSTALL_URL" | bash -s -- --target "codex-cli" "$@"
fi
