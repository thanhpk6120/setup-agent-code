#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/antigravity-pre-tool.ps1" "$@"
exit $?
