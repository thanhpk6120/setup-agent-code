#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js >= 20 is required to run setup-agent-team-ide." >&2
  exit 1
fi

exec node "$DIR/setup.mjs" "$@"
