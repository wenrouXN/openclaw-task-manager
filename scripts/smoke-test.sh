#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke test for task.sh
# Usage: bash smoke-test.sh [TASK_ROOT]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/task.sh"
TASK_ROOT="${1:-${TASK_ROOT:-/tmp/task-smoke-test-$$}}"

export TASK_ROOT
mkdir -p "$TASK_ROOT"/{active,done,failed}

passed=0
failed=0
total=0

run_test() {
    local name="$1"; shift
    total=$((total + 1))
    echo -n "  [$total] $name ... "
    if "$@" >/dev/null 2>&1; then
        echo "✅"
        passed=$((passed + 1))
    else
        echo "❌"
        failed=$((failed + 1))
    fi
}

expect_json_field() {
    local name="$1" field="$2"; shift 2
    total=$((total + 1))
    echo -n "  [$total] $name ... "
    local result
    result=$("$@" 2>&1)
    if echo "$result" | grep -q "$field"; then
        echo "✅"
        passed=$((passed + 1))
    else
        echo "❌ (expected '$field' in: $result)"
        failed=$((failed + 1))
    fi
}

expect_fail() {
    local name="$1"; shift
    total=$((total + 1))
    echo -n "  [$total] $name ... "
    if "$@" >/dev/null 2>&1; then
        echo "❌ (should have failed)"
        failed=$((failed + 1))
    else
        echo "✅"
        passed=$((passed + 1))
    fi
}

echo "=== Task Manager Smoke Test ==="
echo "TASK_ROOT=$TASK_ROOT"
echo ""

# --- Basic CRUD ---
echo "--- Basic CRUD ---"
expect_json_field "create task" "taskId" bash "$SCRIPT" create "Smoke test task" --agent test-agent --priority normal
T1=$(bash "$SCRIPT" list --format json 2>/dev/null | grep -o '"taskId":"[^"]*"' | head -1 | cut -d'"' -f4)
run_test "list shows task" bash "$SCRIPT" list
run_test "status returns info" bash "$SCRIPT" status "$T1"
expect_json_field "update task" "updated" bash "$SCRIPT" update "$T1" --step "Step 1 done" --next-action "Step 2"
expect_json_field "plan task" "taskId" bash "$SCRIPT" plan "$T1" --steps "Step 1,Step 2,Step 3"
run_test "resume info" bash "$SCRIPT" resume "$T1"

# --- Verify + Complete ---
echo ""
echo "--- Verify + Complete ---"
expect_json_field "verify pass" "pass" bash "$SCRIPT" verify "$T1" --result pass
expect_json_field "complete task" "done" bash "$SCRIPT" complete "$T1"
run_test "list-done works" bash "$SCRIPT" list-done
run_test "list-done table format" bash "$SCRIPT" list-done --format table

# --- Reopen ---
echo ""
echo "--- Reopen ---"
expect_json_field "reopen task" "running" bash "$SCRIPT" reopen "$T1"
run_test "task back in active" bash "$SCRIPT" list

# --- Verify fail + Revise ---
echo ""
echo "--- Verify Fail + Revise ---"
expect_json_field "verify fail" "fail" bash "$SCRIPT" verify "$T1" --result fail --issues "bug1,bug2"
expect_json_field "revise task" "taskId" bash "$SCRIPT" revise "$T1" --findings "fix bug1,fix bug2"

# --- Block / Unblock ---
echo ""
echo "--- Block / Unblock ---"
expect_json_field "block task" "blocked" bash "$SCRIPT" block "$T1" "waiting for API key"
expect_json_field "unblock task" "running" bash "$SCRIPT" unblock "$T1"

# --- Fail ---
echo ""
echo "--- Fail ---"
expect_json_field "fail task" "failed" bash "$SCRIPT" fail "$T1" "smoke test cleanup"

# --- Parent-Child ---
echo ""
echo "--- Parent-Child ---"
P=$(bash "$SCRIPT" create "Parent task" --agent test-agent 2>/dev/null | grep -o '"taskId":"[^"]*"' | cut -d'"' -f4)
run_test "create parent" test -n "$P"
C=$(bash "$SCRIPT" create "Child task" --agent test-agent --parent "$P" 2>/dev/null | grep -o '"taskId":"[^"]*"' | cut -d'"' -f4)
run_test "create child" test -n "$C"
run_test "tree shows hierarchy" bash "$SCRIPT" tree
expect_json_field "fail child blocks parent" "parentBlocked" bash "$SCRIPT" fail "$C" "child failed"

# --- Input Validation ---
echo ""
echo "--- Input Validation ---"
expect_fail "reject invalid priority" bash "$SCRIPT" create "test" --agent x --priority bogus
expect_fail "reject invalid status" bash "$SCRIPT" update "$P" --status bogus
expect_fail "reject invalid verify" bash "$SCRIPT" verify "$P" --result bogus

# --- Duplicate Detection ---
echo ""
echo "--- Duplicate Detection ---"
expect_fail "reject duplicate create" bash "$SCRIPT" create "Parent task" --agent test-agent

# --- Cleanup ---
echo ""
echo "--- Cleanup ---"
run_test "orphans scan" bash "$SCRIPT" orphans 1
run_test "rebuild-index" bash "$SCRIPT" rebuild-index

# --- Summary ---
echo ""
echo "=== Results: $passed/$total passed, $failed failed ==="

# Cleanup temp dir
rm -rf "$TASK_ROOT"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
echo "✅ All smoke tests passed"
