#!/usr/bin/env bash
# Integration tests for the Amplifier workgraph executor.
#
# Prerequisites:
#   - wg (workgraph CLI) installed and on PATH
#   - amplifier installed and on PATH
#
# Usage:
#   ./tests/test_integration.sh          # Run all tests
#   ./tests/test_integration.sh --quick  # Skip slow tests (no actual agent spawn)
#
# Exit codes:
#   0 = all tests passed
#   1 = test failure
#   2 = missing prerequisites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QUICK_MODE=false

if [[ "${1:-}" == "--quick" ]]; then
    QUICK_MODE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
    echo -e "  ${GREEN}PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "  ${RED}FAIL${NC}: $1"
    echo -e "        $2"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
    echo -e "  ${YELLOW}SKIP${NC}: $1"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

# --------------------------------------------------------------------------
# Prerequisites
# --------------------------------------------------------------------------
echo "Checking prerequisites..."

if ! command -v wg &>/dev/null; then
    echo -e "${RED}Error: 'wg' not found on PATH.${NC}"
    echo "Install workgraph: https://github.com/graphwork/workgraph"
    exit 2
fi

if ! command -v amplifier &>/dev/null; then
    echo -e "${RED}Error: 'amplifier' not found on PATH.${NC}"
    echo "Install amplifier: https://github.com/microsoft/amplifier"
    exit 2
fi

echo "  wg:        $(which wg)"
echo "  amplifier: $(which amplifier)"
echo ""

# --------------------------------------------------------------------------
# Test 1: Executor TOML is valid
# --------------------------------------------------------------------------
echo "Test 1: Executor TOML validity"

TOML_FILE="$BUNDLE_DIR/executor/amplifier.toml"

if [ ! -f "$TOML_FILE" ]; then
    fail "Executor TOML exists" "File not found: $TOML_FILE"
else
    pass "Executor TOML exists"
fi

# Check required fields using python (TOML parser)
python3 -c "
import tomllib, sys
with open('$TOML_FILE', 'rb') as f:
    cfg = tomllib.load(f)
exc = cfg.get('executor', {})
required = ['type', 'command', 'args', 'working_dir']
missing = [k for k in required if k not in exc]
if missing:
    print(f'Missing fields: {missing}', file=sys.stderr)
    sys.exit(1)
if 'prompt_template' not in exc:
    print('Missing prompt_template section', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && pass "Executor TOML has required fields" \
             || fail "Executor TOML has required fields" "Missing required fields"

# Check template variables are present
python3 -c "
import tomllib, sys
with open('$TOML_FILE', 'rb') as f:
    cfg = tomllib.load(f)
template = cfg['executor']['prompt_template']['template']
required_vars = ['{{task_id}}', '{{task_title}}', '{{task_description}}', '{{task_context}}']
missing = [v for v in required_vars if v not in template]
if missing:
    print(f'Missing template vars: {missing}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && pass "Prompt template has required variables" \
             || fail "Prompt template has required variables" "Missing template variables"

# --------------------------------------------------------------------------
# Test 2: Install script works
# --------------------------------------------------------------------------
echo ""
echo "Test 2: Install script"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Initialize a workgraph project in temp dir
(cd "$TMPDIR" && wg init 2>/dev/null) \
    && pass "wg init in temp dir" \
    || fail "wg init in temp dir" "Failed to initialize workgraph"

# Run install script
"$BUNDLE_DIR/executor/install.sh" "$TMPDIR" &>/dev/null \
    && pass "Install script runs successfully" \
    || fail "Install script runs successfully" "Install script failed"

# Check executor was installed
if [ -f "$TMPDIR/.workgraph/executors/amplifier.toml" ]; then
    pass "Executor TOML installed to correct location"
else
    fail "Executor TOML installed to correct location" "File not found after install"
fi

# Verify installed TOML matches source
if diff -q "$TOML_FILE" "$TMPDIR/.workgraph/executors/amplifier.toml" &>/dev/null; then
    pass "Installed TOML matches source"
else
    fail "Installed TOML matches source" "Files differ"
fi

# Check wrapper script was installed
if [ -f "$TMPDIR/.workgraph/executors/amplifier-run.sh" ]; then
    pass "Wrapper script installed to correct location"
else
    fail "Wrapper script installed to correct location" "amplifier-run.sh not found after install"
fi

# Check wrapper script is executable
if [ -x "$TMPDIR/.workgraph/executors/amplifier-run.sh" ]; then
    pass "Wrapper script is executable"
else
    fail "Wrapper script is executable" "chmod +x not applied by install script"
fi

# --------------------------------------------------------------------------
# Test 3: Install script rejects non-workgraph dirs
# --------------------------------------------------------------------------
echo ""
echo "Test 3: Install script validation"

EMPTY_DIR=$(mktemp -d)
if "$BUNDLE_DIR/executor/install.sh" "$EMPTY_DIR" &>/dev/null; then
    fail "Rejects dir without .workgraph/" "Should have failed for non-workgraph dir"
else
    pass "Rejects dir without .workgraph/"
fi
rm -rf "$EMPTY_DIR"

# --------------------------------------------------------------------------
# Test 4: Wrapper script forwards flags
# --------------------------------------------------------------------------
echo ""
echo "Test 4: Wrapper script flag forwarding"

WRAPPER="$BUNDLE_DIR/executor/amplifier-run.sh"

# Test --model flag forwarding
# We replace 'amplifier' with a stub that echoes its args, then check output
STUB_DIR=$(mktemp -d)
cat > "$STUB_DIR/amplifier" <<'STUB'
#!/usr/bin/env bash
echo "ARGS:" "$@"
STUB
chmod +x "$STUB_DIR/amplifier"

# --model as two args
OUTPUT=$(echo "test prompt" | PATH="$STUB_DIR:$PATH" bash "$WRAPPER" --model gpt-4o 2>/dev/null)
if echo "$OUTPUT" | grep -q -- "--model gpt-4o"; then
    pass "Forwards --model flag (two-arg form)"
else
    fail "Forwards --model flag (two-arg form)" "Got: $OUTPUT"
fi

# --model=value form
OUTPUT=$(echo "test prompt" | PATH="$STUB_DIR:$PATH" bash "$WRAPPER" --model=gpt-4o 2>/dev/null)
if echo "$OUTPUT" | grep -q -- "--model gpt-4o"; then
    pass "Forwards --model flag (equals form)"
else
    fail "Forwards --model flag (equals form)" "Got: $OUTPUT"
fi

# Prompt still arrives as last positional arg
if echo "$OUTPUT" | grep -q "test prompt"; then
    pass "Prompt passed as positional arg after flags"
else
    fail "Prompt passed as positional arg after flags" "Got: $OUTPUT"
fi

# No flags: prompt still works
OUTPUT=$(echo "bare prompt" | PATH="$STUB_DIR:$PATH" bash "$WRAPPER" 2>/dev/null)
if echo "$OUTPUT" | grep -q "bare prompt"; then
    pass "Works with no extra flags"
else
    fail "Works with no extra flags" "Got: $OUTPUT"
fi

rm -rf "$STUB_DIR"

# --------------------------------------------------------------------------
# Test 5: Bundle structure
# --------------------------------------------------------------------------
echo ""
echo "Test 5: Bundle structure"

for f in bundle.md behaviors/workgraph.yaml context/workgraph-guide.md context/wg-executor-protocol.md agents/workgraph-planner.md; do
    if [ -f "$BUNDLE_DIR/$f" ]; then
        pass "File exists: $f"
    else
        fail "File exists: $f" "Not found"
    fi
done

# Check bundle.md has frontmatter
if head -1 "$BUNDLE_DIR/bundle.md" | grep -q "^---"; then
    pass "bundle.md has YAML frontmatter"
else
    fail "bundle.md has YAML frontmatter" "Missing --- delimiter"
fi

# Check agent has meta frontmatter
if head -5 "$BUNDLE_DIR/agents/workgraph-planner.md" | grep -q "meta:"; then
    pass "Agent has meta: frontmatter"
else
    fail "Agent has meta: frontmatter" "Missing meta: section"
fi

# --------------------------------------------------------------------------
# Test 6: Task lifecycle with amplifier executor (slow -- needs LLM call)
# --------------------------------------------------------------------------
echo ""
echo "Test 6: End-to-end task lifecycle"

if $QUICK_MODE; then
    skip "End-to-end lifecycle (--quick mode)"
else
    # Create a fresh workgraph project
    E2E_DIR=$(mktemp -d)

    (cd "$E2E_DIR" && wg init 2>/dev/null)
    "$BUNDLE_DIR/executor/install.sh" "$E2E_DIR" &>/dev/null

    # Add a trivial task
    (cd "$E2E_DIR" && wg add "Create a file called hello.txt containing the word HELLO" 2>/dev/null) \
        && pass "Added test task" \
        || fail "Added test task" "wg add failed"

    # Get the task ID
    TASK_ID=$(cd "$E2E_DIR" && wg list --json 2>/dev/null | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
if tasks:
    print(tasks[0].get('id', ''))
" 2>/dev/null)

    if [ -n "$TASK_ID" ]; then
        pass "Retrieved task ID: $TASK_ID"

        # Spawn with amplifier executor (non-blocking: wg spawn returns after starting the agent)
        echo "  Spawning Amplifier session for task '$TASK_ID' (may take 30-120s)..."
        if (cd "$E2E_DIR" && wg spawn "$TASK_ID" --executor amplifier 2>/dev/null); then
            pass "Spawn initiated without error"

            # Poll for task completion (wg spawn is non-blocking -- agent runs in background)
            echo "  Waiting for agent to complete..."
            DEADLINE=$((SECONDS + 120))
            STATUS="in-progress"
            while [ $SECONDS -lt $DEADLINE ]; do
                sleep 5
                STATUS=$(cd "$E2E_DIR" && wg show "$TASK_ID" --json 2>/dev/null | python3 -c "
import json, sys
task = json.load(sys.stdin)
print(task.get('status', 'unknown'))
" 2>/dev/null)
                if [ "$STATUS" = "done" ] || [ "$STATUS" = "Done" ] || [ "$STATUS" = "failed" ] || [ "$STATUS" = "Failed" ]; then
                    break
                fi
                echo "  Still running (status: $STATUS)..."
            done

            if [ "$STATUS" = "done" ] || [ "$STATUS" = "Done" ]; then
                pass "Task marked as done"
            elif [ "$STATUS" = "failed" ]; then
                REASON=$(cd "$E2E_DIR" && wg show "$TASK_ID" --json 2>/dev/null | python3 -c "
import json, sys
task = json.load(sys.stdin)
print(task.get('failure_reason', 'unknown'))
" 2>/dev/null)
                fail "Task marked as done" "Task failed: $REASON"
                # Show output log for debugging
                echo "  --- Output log ---"
                cat "$E2E_DIR/.workgraph/agents/agent-1/output.log" 2>/dev/null | tail -30
                echo "  --- End log ---"
            else
                fail "Task marked as done" "Timed out waiting -- status is: $STATUS"
            fi

            # Check if hello.txt was created (task explicitly requires it)
            if [ -f "$E2E_DIR/hello.txt" ]; then
                pass "Artifact created: hello.txt"
            else
                fail "Artifact created: hello.txt" "Task marked done but artifact missing"
            fi
        else
            fail "Spawn initiated" "Spawn returned non-zero exit code"
        fi
    else
        fail "Retrieved task ID" "Could not get task ID from wg list"
    fi

    rm -rf "$E2E_DIR"
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "========================================="
echo -e "Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}, ${YELLOW}${SKIP_COUNT} skipped${NC}"
echo "========================================="

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi
exit 0
