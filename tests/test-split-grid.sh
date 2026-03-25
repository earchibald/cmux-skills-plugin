#!/usr/bin/env bash
# Test cmux split-grid composition from 1x1 through 4x4
# Each test creates an isolated workspace, builds the grid, verifies, and tears down.

PASS_COUNT=0
FAIL_COUNT=0

# Parse workspace ref from "OK workspace:N"
parse_workspace() {
    echo "$1" | grep -o 'workspace:[0-9]*'
}

# Parse surface ref from "OK surface:N workspace:N"
parse_surface() {
    echo "$1" | grep -o 'surface:[0-9]*'
}

# Get the first pane in a workspace
get_first_pane() {
    local ws="$1"
    cmux list-panes --workspace "$ws" 2>/dev/null | grep -o 'pane:[0-9]*' | head -1
}

# Get the first surface in a pane
get_first_surface() {
    local ws="$1" pane="$2"
    cmux list-pane-surfaces --workspace "$ws" --pane "$pane" 2>/dev/null | grep -o 'surface:[0-9]*' | head -1
}

# Get all surfaces in a workspace (one per line)
get_all_surfaces() {
    local ws="$1"
    local panes
    panes=$(cmux list-panes --workspace "$ws" 2>/dev/null | grep -o 'pane:[0-9]*')
    for pane in $panes; do
        cmux list-pane-surfaces --workspace "$ws" --pane "$pane" 2>/dev/null | grep -o 'surface:[0-9]*'
    done
}

# Count total cells (surfaces) in a workspace
# Note: down-splits may create surfaces within a pane rather than new panes,
# so we count surfaces across all panes, not pane count.
count_cells() {
    local ws="$1"
    get_all_surfaces "$ws" | wc -l | tr -d ' '
}

test_grid() {
    local cols="$1" rows="$2"
    local expected=$((cols * rows))
    local ws="" cleanup_needed=false

    echo "=== Grid ${cols}x${rows} (${cols} cols, ${rows} rows) ==="

    # Step 1: Create workspace
    local ws_out
    ws_out=$(cmux new-workspace 2>&1)
    ws=$(parse_workspace "$ws_out")
    if [ -z "$ws" ]; then
        echo "FAIL: Grid ${cols}x${rows} — could not create workspace (output: $ws_out)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    cleanup_needed=true
    echo "  Creating workspace... $ws"

    # Step 2: Get initial surface
    local first_pane
    first_pane=$(get_first_pane "$ws")
    if [ -z "$first_pane" ]; then
        echo "FAIL: Grid ${cols}x${rows} — no initial pane"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        [ "$cleanup_needed" = true ] && cmux close-workspace --workspace "$ws" >/dev/null 2>&1
        return
    fi

    local initial_surface
    initial_surface=$(get_first_surface "$ws" "$first_pane")
    if [ -z "$initial_surface" ]; then
        echo "FAIL: Grid ${cols}x${rows} — no initial surface"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        [ "$cleanup_needed" = true ] && cmux close-workspace --workspace "$ws" >/dev/null 2>&1
        return
    fi

    # col_surfaces tracks the "current bottom" surface for each column
    # Used for chaining down-splits correctly
    declare -a col_surfaces
    col_surfaces[0]="$initial_surface"

    echo "  Building grid... $expected cells expected"

    # Step 3: Create columns (right splits)
    local i
    for ((i = 1; i < cols; i++)); do
        local split_out
        split_out=$(cmux new-split right --workspace "$ws" 2>&1)
        local new_surface
        new_surface=$(parse_surface "$split_out")
        if [ -z "$new_surface" ]; then
            echo "FAIL: Grid ${cols}x${rows} — right split $i failed (output: $split_out)"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            [ "$cleanup_needed" = true ] && cmux close-workspace --workspace "$ws" >/dev/null 2>&1
            return
        fi
        col_surfaces[$i]="$new_surface"
    done

    # Step 4: Create rows (down splits per column)
    for ((i = 0; i < cols; i++)); do
        local j
        for ((j = 1; j < rows; j++)); do
            local target="${col_surfaces[$i]}"
            local split_out
            split_out=$(cmux new-split down --workspace "$ws" --surface "$target" 2>&1)
            local new_surface
            new_surface=$(parse_surface "$split_out")
            if [ -z "$new_surface" ]; then
                echo "FAIL: Grid ${cols}x${rows} — down split col=$i row=$j failed (output: $split_out)"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                [ "$cleanup_needed" = true ] && cmux close-workspace --workspace "$ws" >/dev/null 2>&1
                return
            fi
            # Chain: next down-split targets the new bottom surface
            col_surfaces[$i]="$new_surface"
        done
    done

    # Step 5: Verify cell count
    local actual
    actual=$(count_cells "$ws")
    if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: Grid ${cols}x${rows} — expected $expected cells, got $actual"
        cmux tree --workspace "$ws" 2>/dev/null
        FAIL_COUNT=$((FAIL_COUNT + 1))
        [ "$cleanup_needed" = true ] && cmux close-workspace --workspace "$ws" >/dev/null 2>&1
        return
    fi
    echo "  Verifying... $actual cells found"

    # Step 6: Label cells and flash
    echo "  Labeling cells..."
    local surfaces
    surfaces=$(get_all_surfaces "$ws")
    local cell_idx=0
    for surface in $surfaces; do
        local r=$((cell_idx / cols))
        local c=$((cell_idx % cols))
        cmux send --workspace "$ws" --surface "$surface" "echo Cell[$r,$c]" >/dev/null 2>&1
        cmux send-key --workspace "$ws" --surface "$surface" enter >/dev/null 2>&1
        cmux trigger-flash --workspace "$ws" --surface "$surface" >/dev/null 2>&1
        cell_idx=$((cell_idx + 1))
    done

    # Step 7: Sleep for labels to render
    if [ "$expected" -le 9 ]; then
        sleep 0.5
    else
        sleep 1.0
    fi

    # Step 8: Show tree
    echo ""
    cmux tree --workspace "$ws" 2>/dev/null
    echo ""

    echo "PASS: Grid ${cols}x${rows}"
    PASS_COUNT=$((PASS_COUNT + 1))

    # Step 9: Cleanup
    cmux close-workspace --workspace "$ws" >/dev/null 2>&1
}

# Run all grid tests
test_grid 1 1
test_grid 1 2
test_grid 2 1
test_grid 2 2
test_grid 2 3
test_grid 3 2
test_grid 3 3
test_grid 3 4
test_grid 4 3
test_grid 4 4

echo ""
echo "================================"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "================================"

[ "$FAIL_COUNT" -eq 0 ] || exit 1
