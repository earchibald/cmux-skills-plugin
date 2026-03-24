#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/pull-skills.sh v0.62.2 [target_dir]
# Fetches cmux, cmux-browser, cmux-markdown skills from manaflow-ai/cmux at the given tag.

TAG="${1:?Usage: pull-skills.sh <tag> [target_dir]}"
TARGET_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/skills}"
SKILLS=("cmux" "cmux-browser" "cmux-markdown")
REPO="manaflow-ai/cmux"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Fetching skills from $REPO at $TAG..."
git clone --depth 1 --branch "$TAG" "https://github.com/$REPO.git" "$TMPDIR/cmux" 2>/dev/null

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

for skill in "${SKILLS[@]}"; do
    if [ -d "$TMPDIR/cmux/skills/$skill" ]; then
        cp -R "$TMPDIR/cmux/skills/$skill" "$TARGET_DIR/$skill"
        echo "  Copied $skill"
    else
        echo "  WARNING: $skill not found at $TAG" >&2
    fi
done

echo "Skills installed to $TARGET_DIR"
