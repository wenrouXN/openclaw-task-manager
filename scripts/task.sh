#!/usr/bin/env bash
# task.sh — Task lifecycle management v2 (flock + claim conflict + cross-agent takeover)
# Location: skills/task-manager/scripts/task.sh
set -euo pipefail

TASK_ROOT="${TASK_ROOT:-/vol1/1000/config/share/openclaw/state/task}"
ACTIVE_DIR="$TASK_ROOT/active"
DONE_DIR="$TASK_ROOT/done"
FAILED_DIR="$TASK_ROOT/failed"
INDEX_FILE="$TASK_ROOT/index.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$SKILL_DIR/templates/SPEC-TEMPLATE.md"

# --- Locking ---
LOCK_DIR="$TASK_ROOT/.locks"
mkdir -p "$LOCK_DIR"

with_lock() {
    local task_id="$1"; shift
    local lock_file="$LOCK_DIR/$task_id.lock"
    mkdir -p "$LOCK_DIR"
    (
        flock -n 9 || { echo '{"error":"task '"$task_id"' is locked by another process"}'; return 1; }
        "$@"
    ) 9>"$lock_file"
}

with_global_lock() {
    local lock_file="$LOCK_DIR/_global.lock"
    mkdir -p "$LOCK_DIR"
    (
        flock -n 9 || { echo '{"error":"global lock held, retry"}'; return 1; }
        "$@"
    ) 9>"$lock_file"
}

# --- Helpers ---
now_iso() { date +"%Y-%m-%dT%H:%M:%S%:z"; }

next_task_id() {
    local today
    today=$(date +"%Y%m%d")
    local max=0
    for dir in "$ACTIVE_DIR"/T-"$today"-* "$DONE_DIR"/T-"$today"-* "$FAILED_DIR"/T-"$today"-*; do
        [ -d "$dir" ] || continue
        local num
        num=$(basename "$dir" | sed 's/.*-//')
        num=$((10#$num))
        [ "$num" -gt "$max" ] && max=$num
    done
    printf "T-%s-%03d" "$today" $((max + 1))
}

spec_field() {
    grep -m1 "\*\*${2}\*\*:" "$1" 2>/dev/null | sed "s/.*\*\*${2}\*\*: *//" || echo ""
}

find_task_dir() {
    local task_id="$1"
    for d in "$ACTIVE_DIR/$task_id" "$DONE_DIR/$task_id" "$FAILED_DIR/$task_id"; do
        [ -d "$d" ] && echo "$d" && return 0
    done
    return 1
}

count_steps() {
    local spec="$1"
    grep -c "^- \[.\] Step" "$spec" 2>/dev/null || echo 0
}

spec_field_multi() {
    # Return a field that may contain a list (e.g. children: id1,id2,id3)
    grep -m1 "\*\*${2}\*\*:" "$1" 2>/dev/null | sed "s/.*\*\*${2}\*\*: *//" || echo ""
}

get_children_ids() {
    # Get child task IDs from parent's children field
    local spec="$1"
    local children
    children=$(spec_field_multi "$spec" "children")
    [ -z "$children" ] && return 0
    echo "$children" | tr ',' '\n'
}

add_child_to_parent() {
    # Append child ID to parent's children field
    local parent_spec="$1" child_id="$2"
    local existing
    existing=$(spec_field_multi "$parent_spec" "children")
    if [ -z "$existing" ]; then
        sed -i "s|\*\*children\*\*:.*|\*\*children\*\*: $child_id|" "$parent_spec"
    else
        sed -i "s|\*\*children\*\*:.*|\*\*children\*\*: $existing,$child_id|" "$parent_spec"
    fi
}

# --- Commands ---

cmd_create() {
    local desc="" agent_id="" priority="normal" session_key="" parent_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent_id="$2"; shift 2 ;;
            --priority) priority="$2"; shift 2 ;;
            --session) session_key="$2"; shift 2 ;;
            --parent) parent_id="$2"; shift 2 ;;
            *) desc="$1"; shift ;;
        esac
    done
    [ -z "$desc" ] && { echo '{"error":"description required"}'; return 1; }
    [ -z "$agent_id" ] && agent_id="unknown"
    case "$priority" in low|normal|high) ;; *) echo '{"error":"--priority must be low, normal, or high"}'; return 1;; esac

    local task_id task_dir now
    task_id=$(next_task_id)
    task_dir="$ACTIVE_DIR/$task_id"
    now=$(now_iso)
    mkdir -p "$task_dir"

    # If parent specified, register child in parent's SPEC
    local parent_line=""
    if [ -n "$parent_id" ]; then
        local parent_dir
        parent_dir=$(find_task_dir "$parent_id") || { echo "{\"error\":\"parent task $parent_id not found\"}"; return 1; }
        add_child_to_parent "$parent_dir/SPEC.md" "$task_id"
        echo "- $now — 子任务 $task_id 创建于 parent $parent_id" >> "$parent_dir/log.md"
        parent_line="- **parent**: $parent_id"
    fi

    cat > "$task_dir/SPEC.md" <<SPEC
# $task_id: $desc

## 元信息
- **taskId**: $task_id
- **status**: running
- **priority**: $priority
- **owner**: $agent_id
- **created**: $now
- **updated**: $now
- **blockedReason**: 
- **verified**: 
${parent_line}
- **children**: 

## 目标
$desc

## 验收标准
- [ ] 待定义

## 执行计划
- [ ] Step 1: 待定义

## 上下文
- **sourceRepo**: 
- **branch**: 
- **worktree**: 
- **relatedSessions**: $session_key

## 恢复信息
- **lastStep**: 
- **nextAction**: 
- **blockers**: 
- **dependencies**: 

## 决策记录
| 时间 | 决策 | 理由 |
|------|------|------|

## 日志摘要
- $now — 任务创建
SPEC
    cat > "$task_dir/log.md" <<LOG
# $task_id Log

- $now — 任务创建: $desc
LOG
    local result="{\"taskId\":\"$task_id\",\"status\":\"running\",\"desc\":\"$desc\",\"dir\":\"$task_dir\""
    [ -n "$parent_id" ] && result+=",\"parent\":\"$parent_id\""
    result+="}"
    echo "$result"
}

cmd_update() {
    local task_id="" new_status="" step_desc="" last_step="" next_action="" blocked_reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) new_status="$2"; shift 2 ;;
            --step) step_desc="$2"; shift 2 ;;
            --last-step) last_step="$2"; shift 2 ;;
            --next-action) next_action="$2"; shift 2 ;;
            --blocked-reason) blocked_reason="$2"; shift 2 ;;
            *) task_id="$1"; shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }
    local spec="$task_dir/SPEC.md"
    local now
    now=$(now_iso)

    if [ -n "$new_status" ]; then
        case "$new_status" in running|blocked|done|failed) ;; *) echo '{"error":"--status must be running, blocked, done, or failed"}'; return 1;; esac
        sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: $new_status/" "$spec"
    fi
    [ -n "$step_desc" ] && echo "- $now — $step_desc" >> "$task_dir/log.md"
    [ -n "$last_step" ] && sed -i "s|\*\*lastStep\*\*:.*|\*\*lastStep\*\*: $last_step|" "$spec"
    [ -n "$next_action" ] && sed -i "s|\*\*nextAction\*\*:.*|\*\*nextAction\*\*: $next_action|" "$spec"
    [ -n "$blocked_reason" ] && sed -i "s|\*\*blockers\*\*:.*|\*\*blockers\*\*: $blocked_reason|" "$spec"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "{\"taskId\":\"$task_id\",\"updated\":\"$now\"}"
}

cmd_plan() {
    local task_id="" steps_json=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --steps) steps_json="$2"; shift 2 ;;
            *) task_id="$1"; shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }
    local spec="$task_dir/SPEC.md"
    local now
    now=$(now_iso)

    # Build plan section
    local plan_section=""
    local i=1
    local warn=""
    IFS=',' read -ra steps <<< "$steps_json"
    for step in "${steps[@]}"; do
        step=$(echo "$step" | xargs)
        plan_section+="- [ ] Step $i: $step"$'\n'
        i=$((i + 1))
    done
    local total=$((i-1))
    [ "$total" -gt 10 ] && warn="WARNING: $total steps exceeds recommended max of 10. Consider splitting."

    # Replace plan section using awk
    local tmp="$spec.tmp"
    awk -v plan="$plan_section" '
        /^## 执行计划/ { print; print ""; printf "%s", plan; skip=1; next }
        skip && /^- \[/ { next }
        skip && /^- \[\]/ { next }
        skip && /^$/ { skip=0; next }
        skip && /^##/ { skip=0 }
        { print }
    ' "$spec" > "$tmp" && mv "$tmp" "$spec"

    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 执行计划已更新（$total 步）" >> "$task_dir/log.md"
    local result="{\"taskId\":\"$task_id\",\"steps\":$total"
    [ -n "$warn" ] && result+=",\"warning\":\"$warn\""
    result+="}"
    echo "$result"
}

cmd_complete() {
    local task_id="$1" force=0
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=1; shift ;;
            *) shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -d "$ACTIVE_DIR/$task_id" ] || { echo "{\"error\":\"task $task_id not found in active\"}"; return 1; }

    local spec="$ACTIVE_DIR/$task_id/SPEC.md"
    local verified
    verified=$(spec_field "$spec" "verified")

    # Guard: must verify before complete (unless --force)
    if [ "$force" -eq 0 ] && [ "$verified" != "pass" ]; then
        echo "{\"error\":\"task $task_id not verified. Run verify --result pass first, or use --force to skip.\",\"verified\":\"${verified:-none}\"}"
        return 1
    fi

    # Guard: all children must be done (unless --force)
    if [ "$force" -eq 0 ]; then
        local children
        children=$(get_children_ids "$spec")
        if [ -n "$children" ]; then
            local pending=""
            while IFS= read -r child_id; do
                [ -z "$child_id" ] && continue
                local child_dir
                child_dir=$(find_task_dir "$child_id") || continue
                local child_status
                child_status=$(spec_field "$child_dir/SPEC.md" "status")
                if [ "$child_status" != "done" ]; then
                    pending+="$child_id($child_status),"
                fi
            done <<< "$children"
            if [ -n "$pending" ]; then
                pending=${pending%,}
                echo "{\"error\":\"task $task_id has unfinished children\",\"pending\":\"$pending\",\"hint\":\"complete children first or use --force\"}"
                return 1
            fi
        fi
    fi

    local now
    now=$(now_iso)
    sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: done/" "$spec"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 任务完成" >> "$ACTIVE_DIR/$task_id/log.md"
    mv "$ACTIVE_DIR/$task_id" "$DONE_DIR/$task_id"
    rm -f "$LOCK_DIR/$task_id.lock"
    echo "{\"taskId\":\"$task_id\",\"status\":\"done\"}"
}

cmd_fail() {
    local task_id="$1" reason="${2:-no reason}"
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -d "$ACTIVE_DIR/$task_id" ] || { echo "{\"error\":\"task $task_id not found in active\"}"; return 1; }

    local now spec="$ACTIVE_DIR/$task_id/SPEC.md"
    now=$(now_iso)
    sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: failed/" "$spec"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 任务失败: $reason" >> "$ACTIVE_DIR/$task_id/log.md"
    mv "$ACTIVE_DIR/$task_id" "$FAILED_DIR/$task_id"
    rm -f "$LOCK_DIR/$task_id.lock"

    # Auto-block parent if this is a child task
    local parent_id
    parent_id=$(spec_field "$FAILED_DIR/$task_id/SPEC.md" "parent")
    if [ -n "$parent_id" ]; then
        local parent_dir
        parent_dir=$(find_task_dir "$parent_id") || true
        if [ -n "$parent_dir" ]; then
            local parent_status
            parent_status=$(spec_field "$parent_dir/SPEC.md" "status")
            if [ "$parent_status" = "running" ]; then
                sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: blocked/" "$parent_dir/SPEC.md"
                sed -i "s/\*\*blockedReason\*\*: .*/\*\*blockedReason\*\*: child $task_id failed: $reason/" "$parent_dir/SPEC.md"
                sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$parent_dir/SPEC.md"
                echo "- $now — 自动阻塞: 子任务 $task_id 失败 ($reason)" >> "$parent_dir/log.md"
            fi
        fi
    fi

    echo "{\"taskId\":\"$task_id\",\"status\":\"failed\",\"reason\":\"$reason\""
    [ -n "$parent_id" ] && echo -n ",\"parentBlocked\":true"
    echo "}"
}

cmd_verify() {
    local task_id="" result="" issues=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --result) result="$2"; shift 2 ;;
            --issues) issues="$2"; shift 2 ;;
            *) task_id="$1"; shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -z "$result" ] && { echo '{"error":"--result pass|fail required"}'; return 1; }
    case "$result" in pass|fail) ;; *) echo '{"error":"--result must be pass or fail"}'; return 1;; esac

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }
    local spec="$task_dir/SPEC.md"
    local now
    now=$(now_iso)

    # Add verified field to SPEC.md if not present
    if grep -q '\*\*verified\*\*:' "$spec"; then
        sed -i "s/\*\*verified\*\*: .*/\*\*verified\*\*: $result/" "$spec"
    else
        sed -i "/\*\*blockedReason\*\*:/i - **verified**: $result" "$spec"
    fi
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"

    if [ "$result" = "pass" ]; then
        echo "- $now — ✅ 验证通过" >> "$task_dir/log.md"
        echo "{\"taskId\":\"$task_id\",\"verified\":\"pass\",\"message\":\"Ready to complete.\"}"
    elif [ "$result" = "fail" ]; then
        echo "- $now — ❌ 验证失败: $issues" >> "$task_dir/log.md"
        # Append issues to execution plan as new steps
        if [ -n "$issues" ]; then
            local tmp_plan="$task_dir/.plan_add"
            : > "$tmp_plan"
            IFS=',' read -ra issue_list <<< "$issues"
            local step_num
            step_num=$(count_steps "$spec")
            for issue in "${issue_list[@]}"; do
                issue=$(echo "$issue" | xargs)
                step_num=$((step_num + 1))
                echo "- [ ] Step $step_num: [verify-fail] $issue" >> "$tmp_plan"
            done
            # Use awk for single-pass insertion before 恢复信息
            awk '/^## 恢复信息/{while((getline line < "'$tmp_plan'") > 0) print line} {print}' "$spec" > "$spec.tmp" && mv "$spec.tmp" "$spec"
            rm -f "$tmp_plan"
        fi
        echo "{\"taskId\":\"$task_id\",\"verified\":\"fail\",\"issues\":\"$issues\"}"
    else
        echo "{\"error\":\"--result must be pass or fail\"}"
        return 1
    fi
}

cmd_reopen() {
    local task_id="$1"
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -d "$DONE_DIR/$task_id" ] || { echo "{\"error\":\"task $task_id not found in done (can only reopen completed tasks)\"}"; return 1; }

    local now
    now=$(now_iso)
    # Move back to active
    mv "$DONE_DIR/$task_id" "$ACTIVE_DIR/$task_id"
    local spec="$ACTIVE_DIR/$task_id/SPEC.md"
    sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: running/" "$spec"
    sed -i "s/\*\*verified\*\*: .*/\*\*verified\*\*: /" "$spec" 2>/dev/null || true
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 任务重新打开（从 done 回到 running）" >> "$ACTIVE_DIR/$task_id/log.md"
    rm -f "$LOCK_DIR/$task_id.lock"
    echo "{\"taskId\":\"$task_id\",\"status\":\"running\",\"message\":\"Task reopened.\"}"
}

cmd_revise() {
    local task_id="" findings=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --findings) findings="$2"; shift 2 ;;
            *) task_id="$1"; shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -z "$findings" ] && { echo '{"error":"--findings required"}'; return 1; }

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }
    local spec="$task_dir/SPEC.md"
    local now
    now=$(now_iso)

    # Append findings as new steps to execution plan
    local tmp_plan="$task_dir/.plan_add"
    : > "$tmp_plan"
    IFS=',' read -ra finding_list <<< "$findings"
    local step_num
    step_num=$(count_steps "$spec")
    for finding in "${finding_list[@]}"; do
        finding=$(echo "$finding" | xargs)
        step_num=$((step_num + 1))
        echo "- [ ] Step $step_num: [修订] $finding" >> "$tmp_plan"
    done
    awk '/^## 恢复信息/{while((getline line < "'$tmp_plan'") > 0) print line} {print}' "$spec" > "$spec.tmp" && mv "$spec.tmp" "$spec"
    rm -f "$tmp_plan"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 修订: 新增 ${#finding_list[@]} 个步骤" >> "$task_dir/log.md"
    echo "{\"taskId\":\"$task_id\",\"revised\":true,\"newSteps\":${#finding_list[@]}}"
}

cmd_block() {
    local task_id="$1" reason="${2:-no reason}"
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -d "$ACTIVE_DIR/$task_id" ] || { echo "{\"error\":\"task $task_id not found in active\"}"; return 1; }

    local now spec="$ACTIVE_DIR/$task_id/SPEC.md"
    now=$(now_iso)
    sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: blocked/" "$spec"
    sed -i "s/\*\*blockedReason\*\*: .*/\*\*blockedReason\*\*: $reason/" "$spec"
    sed -i "s|\*\*blockers\*\*:.*|\*\*blockers\*\*: $reason|" "$spec"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 任务阻塞: $reason" >> "$ACTIVE_DIR/$task_id/log.md"
    echo "{\"taskId\":\"$task_id\",\"status\":\"blocked\",\"reason\":\"$reason\"}"
}

cmd_unblock() {
    local task_id="$1"
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -d "$ACTIVE_DIR/$task_id" ] || { echo "{\"error\":\"task $task_id not found in active\"}"; return 1; }

    local now spec="$ACTIVE_DIR/$task_id/SPEC.md"
    now=$(now_iso)
    sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: running/" "$spec"
    sed -i "s/\*\*blockedReason\*\*: .*/\*\*blockedReason\*\*: /" "$spec"
    sed -i "s|\*\*blockers\*\*:.*|\*\*blockers\*\*: |" "$spec"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    echo "- $now — 任务解除阻塞" >> "$ACTIVE_DIR/$task_id/log.md"
    echo "{\"taskId\":\"$task_id\",\"status\":\"running\"}"
}

# --- claim: with conflict detection + cross-agent takeover ---
cmd_claim() {
    local task_id="" new_session="" agent_id="" force=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) new_session="$2"; shift 2 ;;
            --agent) agent_id="$2"; shift 2 ;;
            --force) force=1; shift ;;
            *) task_id="$1"; shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }
    local spec="$task_dir/SPEC.md"
    local now
    now=$(now_iso)

    # Conflict detection
    local current_owner current_sessions current_status
    current_owner=$(spec_field "$spec" "owner")
    current_sessions=$(spec_field "$spec" "relatedSessions")
    current_status=$(spec_field "$spec" "status")

    if [ "$current_status" = "done" ] || [ "$current_status" = "failed" ]; then
        echo "{\"error\":\"task $task_id is $current_status, cannot claim\",\"status\":\"$current_status\"}"
        return 1
    fi

    # If already owned by a different agent and not --force, report conflict
    if [ -n "$current_owner" ] && [ "$current_owner" != "unknown" ] && [ "$current_owner" != "$agent_id" ] && [ "$force" -eq 0 ]; then
        echo "{\"conflict\":true,\"taskId\":\"$task_id\",\"currentOwner\":\"$current_owner\",\"currentSessions\":\"$current_sessions\",\"hint\":\"use --force to takeover\"}"
        return 2
    fi

    # Proceed with claim
    [ -n "$new_session" ] && sed -i "s|\*\*relatedSessions\*\*:.*|\*\*relatedSessions\*\*: $new_session|" "$spec"
    [ -n "$agent_id" ] && sed -i "s|\*\*owner\*\*:.*|\*\*owner\*\*: $agent_id|" "$spec"
    sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
    local takeover_msg=""
    [ "$force" -eq 1 ] && takeover_msg=" (forced takeover from $current_owner)"
    echo "- $now — 任务被接管 agent:$agent_id session:$new_session$takeover_msg" >> "$task_dir/log.md"
    echo "{\"taskId\":\"$task_id\",\"claimed\":true,\"owner\":\"$agent_id\",\"forced\":$([ $force -eq 1 ] && echo true || echo false)}"
}

# --- takeover: explicit cross-agent takeover shorthand ---
cmd_takeover() {
    local task_id="" new_session="" agent_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session) new_session="$2"; shift 2 ;;
            --agent) agent_id="$2"; shift 2 ;;
            *) task_id="$1"; shift ;;
        esac
    done
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [ -z "$agent_id" ] && { echo '{"error":"--agent required for takeover"}'; return 1; }

    local claim_args=("$task_id" --agent "$agent_id" --force)
    [ -n "$new_session" ] && claim_args+=(--session "$new_session")
    cmd_claim "${claim_args[@]}"
    rm -f "$LOCK_DIR/$task_id.lock"
}

cmd_orphans() {
    local stale_hours="${1:-24}"
    local now_epoch
    now_epoch=$(date +%s)
    local orphans=""
    local first=true

    for dir in "$ACTIVE_DIR"/T-*; do
        [ -d "$dir" ] || continue
        local spec="$dir/SPEC.md"
        [ -f "$spec" ] || continue
        local updated task_id owner status
        updated=$(spec_field "$spec" "updated")
        task_id=$(basename "$dir")
        owner=$(spec_field "$spec" "owner")
        status=$(spec_field "$spec" "status")

        [ "$status" = "done" ] || [ "$status" = "failed" ] && continue

        # Parse age
        local updated_epoch
        updated_epoch=$(date -d "$updated" +%s 2>/dev/null || echo 0)
        [ "$updated_epoch" -eq 0 ] && continue
        local age_hours=$(( (now_epoch - updated_epoch) / 3600 ))

        if [ "$age_hours" -ge "$stale_hours" ]; then
            if $first; then first=false; else orphans+=","; fi
            orphans+="{\"taskId\":\"$task_id\",\"owner\":\"$owner\",\"status\":\"$status\",\"staleHours\":$age_hours,\"updated\":\"$updated\"}"
        fi
    done
    echo "{\"staleThreshold\":\"${stale_hours}h\",\"orphans\":[$orphans]}"
}

cmd_list() {
    local filter_status="" filter_agent="" format="json"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) filter_status="$2"; shift 2 ;;
            --agent) filter_agent="$2"; shift 2 ;;
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local tasks=()
    for dir in "$ACTIVE_DIR"/T-*; do
        [ -d "$dir" ] || continue
        local task_id spec status agent_id desc priority updated last_step next_action blocked_reason
        task_id=$(basename "$dir")
        spec="$dir/SPEC.md"
        [ -f "$spec" ] || continue
        status=$(spec_field "$spec" "status")
        agent_id=$(spec_field "$spec" "owner")
        [ -n "$filter_status" ] && [ "$status" != "$filter_status" ] && continue
        [ -n "$filter_agent" ] && [ "$agent_id" != "$filter_agent" ] && continue
        desc=$(grep -m1 "^# $task_id:" "$spec" | sed "s/^# $task_id: //")
        priority=$(spec_field "$spec" "priority")
        updated=$(spec_field "$spec" "updated")
        last_step=$(spec_field "$spec" "lastStep")
        next_action=$(spec_field "$spec" "nextAction")
        blocked_reason=$(spec_field "$spec" "blockedReason")

        if [ "$format" = "table" ]; then
            printf "%-16s %-8s %-8s %-12s %-20s %s\n" "$task_id" "$status" "$priority" "$agent_id" "${updated:0:16}" "$desc"
        else
            tasks+=("{\"taskId\":\"$task_id\",\"status\":\"$status\",\"priority\":\"$priority\",\"owner\":\"$agent_id\",\"updated\":\"$updated\",\"desc\":\"$desc\",\"lastStep\":\"$last_step\",\"nextAction\":\"$next_action\",\"blockedReason\":\"$blocked_reason\"}")
        fi
    done

    if [ "$format" = "table" ]; then
        echo ""
    else
        local result="[" first=true
        for t in "${tasks[@]}"; do
            $first && first=false || result+=","
            result+="$t"
        done
        result+="]"
        echo "{\"count\":${#tasks[@]},\"tasks\":$result}"
    fi
}

cmd_list_done() {
    local filter_agent="" limit=10 format="json"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) filter_agent="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local count=0
    if [ "$format" = "table" ]; then
        printf "%-16s %-12s %-20s %s\n" "TASK" "OWNER" "UPDATED" "DESC"
        printf "%-16s %-12s %-20s %s\n" "----" "-----" "-------" "----"
    fi
    for dir in "$DONE_DIR"/T-*; do
        [ -d "$dir" ] || continue
        [ "$count" -ge "$limit" ] && break
        local task_id spec agent_id desc updated
        task_id=$(basename "$dir")
        spec="$dir/SPEC.md"
        [ -f "$spec" ] || continue
        agent_id=$(spec_field "$spec" "owner")
        [ -n "$filter_agent" ] && [ "$agent_id" != "$filter_agent" ] && continue
        desc=$(grep -m1 "^# $task_id:" "$spec" | sed "s/^# $task_id: //")
        updated=$(spec_field "$spec" "updated")
        count=$((count + 1))
        if [ "$format" = "table" ]; then
            printf "%-16s %-12s %-20s %s\n" "$task_id" "$agent_id" "${updated:0:16}" "$desc"
        else
            echo "{\"taskId\":\"$task_id\",\"owner\":\"$agent_id\",\"updated\":\"$updated\",\"desc\":\"$desc\"}"
        fi
    done
    [ "$format" = "table" ] && echo ""
}

cmd_resume_info() {
    local task_id="$1" format="json"
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }
    local spec="$task_dir/SPEC.md"

    local status owner updated desc last_step next_action blocked_reason
    status=$(spec_field "$spec" "status")
    owner=$(spec_field "$spec" "owner")
    updated=$(spec_field "$spec" "updated")
    desc=$(grep -m1 "^# $task_id:" "$spec" | sed "s/^# $task_id: //")
    last_step=$(spec_field "$spec" "lastStep")
    next_action=$(spec_field "$spec" "nextAction")
    blocked_reason=$(spec_field "$spec" "blockedReason")

    local recent_log
    recent_log=$(tail -5 "$task_dir/log.md" 2>/dev/null | tr '\n' '|' | sed 's/|$//')

    local pending_steps
    pending_steps=$(grep "^- \[ \] Step" "$spec" 2>/dev/null | head -10 | tr '\n' '|' | sed 's/|$//')

    if [ "$format" = "table" ]; then
        echo "=== $task_id ==="
        echo "Status: $status | Owner: $owner"
        echo "Desc: $desc"
        [ -n "$last_step" ] && echo "Last: $last_step"
        [ -n "$next_action" ] && echo "Next: $next_action"
        [ -n "$blocked_reason" ] && echo "Blocked: $blocked_reason"
        echo ""
        echo "Recent log:"
        echo "$recent_log" | tr '|' '\n'
        echo ""
        echo "Pending steps:"
        echo "$pending_steps" | tr '|' '\n'
    else
        echo "{\"taskId\":\"$task_id\",\"status\":\"$status\",\"owner\":\"$owner\",\"updated\":\"$updated\",\"desc\":\"$desc\",\"lastStep\":\"$last_step\",\"nextAction\":\"$next_action\",\"blockedReason\":\"$blocked_reason\",\"recentLog\":\"$recent_log\",\"pendingSteps\":\"$pending_steps\"}"
    fi
}

cmd_cleanup() {
    local stale_days=3 dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stale-days) stale_days="$2"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            *) shift ;;
        esac
    done

    local now_epoch now cleaned=0 flagged=0
    now_epoch=$(date +%s)
    now=$(now_iso)

    for dir in "$ACTIVE_DIR"/T-*; do
        [ -d "$dir" ] || continue
        local spec="$dir/SPEC.md"
        [ -f "$spec" ] || continue
        local task_id updated updated_epoch status age
        task_id=$(basename "$dir")
        updated=$(spec_field "$spec" "updated")
        status=$(spec_field "$spec" "status")
        updated_epoch=$(date -d "$updated" +%s 2>/dev/null || echo 0)
        [ "$updated_epoch" -eq 0 ] && continue
        age=$((now_epoch - updated_epoch))

        if [ "$status" = "blocked" ] && [ "$age" -gt $((stale_days * 86400)) ]; then
            if [ "$dry_run" -eq 1 ]; then
                echo "{\"taskId\":\"$task_id\",\"status\":\"blocked\",\"age_days\":$((age/86400)),\"action\":\"would_archive\"}"
                flagged=$((flagged + 1))
            else
                sed -i "s/\*\*status\*\*: .*/\*\*status\*\*: failed/" "$spec"
                sed -i "s/\*\*updated\*\*: .*/\*\*updated\*\*: $now/" "$spec"
                echo "- $now — 自动归档: blocked 超过 ${stale_days} 天" >> "$dir/log.md"
                mv "$dir" "$FAILED_DIR/$task_id"
                cleaned=$((cleaned + 1))
                echo "{\"taskId\":\"$task_id\",\"status\":\"failed\",\"age_days\":$((age/86400)),\"action\":\"archived\"}"
            fi
        fi
    done
    echo "{\"cleaned\":$cleaned,\"flagged\":$flagged,\"stale_days\":$stale_days,\"dry_run\":$dry_run}"
}

cmd_rebuild_index() {
    local ac=0 dc=0 fc=0
    for dir in "$ACTIVE_DIR"/T-*; do [ -d "$dir" ] && ac=$((ac+1)); done
    for dir in "$DONE_DIR"/T-*; do [ -d "$dir" ] && dc=$((dc+1)); done
    for dir in "$FAILED_DIR"/T-*; do [ -d "$dir" ] && fc=$((fc+1)); done
    cat > "$INDEX_FILE" <<EOF
{
  "schemaVersion": "3.0",
  "lastUpdated": "$(now_iso)",
  "stats": {"active":$ac,"done":$dc,"failed":$fc,"total":$((ac+dc+fc))}
}
EOF
    echo "{\"active\":$ac,\"done\":$dc,\"failed\":$fc}"
}

cmd_status() {
    local task_id="$1" format="json"
    [ -z "$task_id" ] && { echo '{"error":"taskId required"}'; return 1; }
    [[ "${2:-}" == "--format" ]] && format="$3"

    local task_dir
    task_dir=$(find_task_dir "$task_id") || { echo "{\"error\":\"task $task_id not found\"}"; return 1; }

    local spec="$task_dir/SPEC.md"
    local status agent_id priority updated desc last_step next_action blocked_reason
    status=$(spec_field "$spec" "status")
    agent_id=$(spec_field "$spec" "owner")
    priority=$(spec_field "$spec" "priority")
    updated=$(spec_field "$spec" "updated")
    desc=$(grep -m1 "^# $task_id:" "$spec" | sed "s/^# $task_id: //")
    last_step=$(spec_field "$spec" "lastStep")
    next_action=$(spec_field "$spec" "nextAction")
    blocked_reason=$(spec_field "$spec" "blockedReason")

    if [ "$format" = "table" ]; then
        echo "Task: $task_id"
        echo "Status: $status | Priority: $priority | Owner: $agent_id"
        echo "Updated: $updated"
        echo "Desc: $desc"
        [ -n "$last_step" ] && echo "Last Step: $last_step"
        [ -n "$next_action" ] && echo "Next Action: $next_action"
        [ -n "$blocked_reason" ] && echo "Blocked: $blocked_reason"
    else
        echo "{\"taskId\":\"$task_id\",\"status\":\"$status\",\"priority\":\"$priority\",\"owner\":\"$agent_id\",\"updated\":\"$updated\",\"desc\":\"$desc\",\"lastStep\":\"$last_step\",\"nextAction\":\"$next_action\",\"blockedReason\":\"$blocked_reason\"}"
    fi
}


cmd_tree() {
    local agent_filter="" format="tree"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent) agent_filter="$2"; shift 2 ;;
            --format) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Find root tasks (tasks with no parent)
    local roots=""
    for dir in "$ACTIVE_DIR"/T-* "$DONE_DIR"/T-* "$FAILED_DIR"/T-*; do
        [ -d "$dir" ] || continue
        local spec="$dir/SPEC.md"
        [ -f "$spec" ] || continue
        local parent children
        parent=$(spec_field "$spec" "parent")
        children=$(spec_field_multi "$spec" "children")
        # Root = has children but no parent
        if [ -z "$parent" ] && [ -n "$children" ]; then
            local task_id agent_id status desc
            task_id=$(basename "$dir")
            agent_id=$(spec_field "$spec" "owner")
            status=$(spec_field "$spec" "status")
            desc=$(grep -m1 "^# $task_id:" "$spec" | sed "s/^# $task_id: //")
            if [ -n "$agent_filter" ] && [ "$agent_id" != "$agent_filter" ]; then
                continue
            fi
            roots+="$task_id|$agent_id|$status|$desc|$children\n"
        fi
    done

    if [ -z "$roots" ]; then
        echo "(no task trees found)"
        return 0
    fi

    # Render tree
    printf "%-20s %-12s %-10s %s\n" "TASK" "OWNER" "STATUS" "DESC"
    printf "%-20s %-12s %-10s %s\n" "----" "-----" "------" "----"
    echo -e "$roots" | while IFS='|' read -r tid owner status desc children; do
        [ -z "$tid" ] && continue
        local icon="✅"
        [ "$status" = "running" ] && icon="🔄"
        [ "$status" = "blocked" ] && icon="🚫"
        [ "$status" = "failed" ] && icon="❌"
        printf "%-20s %-12s %-10s %s\n" "$tid" "$owner" "$icon $status" "$desc"
        # Print children
        if [ -n "$children" ]; then
            IFS=',' read -ra child_list <<< "$children"
            for child_id in "${child_list[@]}"; do
                child_id=$(echo "$child_id" | xargs)
                [ -z "$child_id" ] && continue
                local child_dir
                child_dir=$(find_task_dir "$child_id") || continue
                local child_spec="$child_dir/SPEC.md"
                local child_agent child_status child_desc
                child_agent=$(spec_field "$child_spec" "owner")
                child_status=$(spec_field "$child_spec" "status")
                child_desc=$(grep -m1 "^# $child_id:" "$child_spec" | sed "s/^# $child_id: //")
                local cicon="✅"
                [ "$child_status" = "running" ] && cicon="🔄"
                [ "$child_status" = "blocked" ] && cicon="🚫"
                [ "$child_status" = "failed" ] && cicon="❌"
                printf "  └─ %-16s %-12s %-10s %s\n" "$child_id" "$child_agent" "$cicon $child_status" "$child_desc"
            done
        fi
    done
}

# --- Dispatch ---
case "${1:-help}" in
    create)   shift; cmd_create "$@" ;;
    update)   shift; with_lock "${1:-_}" cmd_update "$@" ;;
    plan)     shift; with_lock "${1:-_}" cmd_plan "$@" ;;
    complete) shift; with_lock "${1:-_}" cmd_complete "$@" ;;
    tree)     shift; cmd_tree "$@" ;;
    verify)   shift; with_lock "${1:-_}" cmd_verify "$@" ;;
    reopen)   shift; with_lock "${1:-_}" cmd_reopen "$@" ;;
    revise)   shift; with_lock "${1:-_}" cmd_revise "$@" ;;
    fail)     shift; with_lock "${1:-_}" cmd_fail "$@" ;;
    block)    shift; with_lock "${1:-_}" cmd_block "$@" ;;
    unblock)  shift; with_lock "${1:-_}" cmd_unblock "$@" ;;
    claim)    shift; with_lock "${1:-_}" cmd_claim "$@" ;;
    takeover) shift; with_lock "${1:-_}" cmd_takeover "$@" ;;
    list)     shift; cmd_list "$@" ;;
    list-done) shift; cmd_list_done "$@" ;;
    orphans)  shift; cmd_orphans "$@" ;;
    resume)   shift; cmd_resume_info "$@" ;;
    cleanup)  shift; cmd_cleanup "$@" ;;
    rebuild-index) cmd_rebuild_index ;;
    status)   shift; cmd_status "$@" ;;
    help|*)
        cat <<'HELP'
task.sh — Task lifecycle management v2

USAGE:
  task.sh <command> [options]

COMMANDS:
  create <desc>          Create task (--agent, --priority, --session)
  update <taskId>        Update task (--status, --step, --last-step, --next-action)
  plan <taskId>          Set execution plan (--steps "step1,step2,step3")
  complete <taskId>      Mark done (requires verify pass, --force to skip)
  tree                   Show task hierarchy (--agent <id>)
  verify <taskId>        Verify task (--result pass|fail [--issues "i1,i2"])
  reopen <taskId>        Reopen completed task back to running
  revise <taskId>        Add revision steps (--findings "fix1,fix2")
  fail <taskId> [reason] Mark failed (moves to failed/)
  block <taskId> [reason] Mark blocked
  unblock <taskId>       Clear blocked
  claim <taskId>         Claim task (--agent, --session) [conflict detection]
  takeover <taskId>      Force cross-agent takeover (--agent, --session)
  list                   List active tasks (--status, --agent, --format table|json)
  list-done              List completed tasks (--agent, --limit N, --format table|json)
  orphans [hours]        Find stale tasks (default: 24h without update)
  resume <taskId>        Get resume info (last step, next action, pending steps)
  cleanup                Auto-archive stale tasks (--stale-days N, --dry-run)
  rebuild-index          Rebuild index.json
  status <taskId>        Get task status (--format table|json)

SAFETY:
  - File locking (flock) prevents concurrent write corruption
  - claim detects ownership conflicts; use --force or takeover to override
  - orphans helps find abandoned tasks for cross-agent pickup
  - plan warns when steps > 10
HELP
        ;;
esac
