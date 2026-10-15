#!/usr/bin/env bash
# Wrapper install.sh cho dsh
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_INSTALL="$DIR/../install.sh"
if [[ -f "$ROOT_INSTALL" ]]; then
  exec bash "$ROOT_INSTALL" --target "dsh" "$@"
else
  echo "Loi: Khong tim thay $ROOT_INSTALL" >&2
  exit 1
fi
