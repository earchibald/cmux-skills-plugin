#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
HOOK="$REPO_ROOT/hooks/session-start"
PASS=0
FAIL=0

run_with_cmux_version() {
    local version="$1"
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "$tmpdir/cmux" <<CMUX
#!/usr/bin/env bash
echo "cmux $version (99) [abc1234]"
CMUX
    chmod +x "$tmpdir/cmux"
    PATH="$tmpdir:$PATH" CMUX_SKILLS_ROOT="$REPO_ROOT" "$HOOK" 2>&1
    local exit_code=$?
    rm -rf "$tmpdir"
    return $exit_code
}

run_without_cmux() {
    PATH="/usr/bin:/bin" CMUX_SKILLS_ROOT="$REPO_ROOT" "$HOOK" 2>&1
}

assert_contains() {
    local output="$1" expected="$2" label="$3"
    if echo "$output" | grep -q "$expected"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (expected '$expected' in output: '$output')"
        FAIL=$((FAIL + 1))
    fi
}

assert_empty() {
    local output="$1" label="$2"
    if [ -z "$output" ]; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (expected empty output, got: '$output')"
        FAIL=$((FAIL + 1))
    fi
}

PINNED=$(python3 -c "import json; print(json.load(open('$REPO_ROOT/.claude-plugin/plugin.json'))['cmux_version'])")

echo "--- Test 1: Version match ---"
OUTPUT=$(run_with_cmux_version "$PINNED")
assert_empty "$OUTPUT" "version match produces no output"

echo "--- Test 2: cmux newer ---"
OUTPUT=$(run_with_cmux_version "99.99.99")
assert_contains "$OUTPUT" "skills are behind" "cmux newer warns about skills being behind"

echo "--- Test 3: cmux older ---"
OUTPUT=$(run_with_cmux_version "0.0.1")
assert_contains "$OUTPUT" "expect newer cmux" "cmux older warns about expecting newer cmux"

echo "--- Test 4: cmux not found ---"
OUTPUT=$(run_without_cmux)
assert_contains "$OUTPUT" "cmux not found" "missing cmux warns about installation"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
