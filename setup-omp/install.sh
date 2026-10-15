#!/usr/bin/env bash
# Wrapper install.sh cho omp
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_INSTALL="$DIR/../install.sh"
if [[ -f "$ROOT_INSTALL" ]]; then
  exec bash "$ROOT_INSTALL" --target "omp" "$@"
else
  echo "Loi: Khong tim thay $ROOT_INSTALL" >&2
  exit 1
fi
