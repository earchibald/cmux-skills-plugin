#!/usr/bin/env bash
set -euo pipefail
HOOK_NAME="$1"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
export CMUX_SKILLS_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOOK_DIR/..}"
exec "$HOOK_DIR/$HOOK_NAME"
