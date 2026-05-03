解读：
#!/usr/bin/env bash
#===============================================================================
# Checkpoint 脚本 - State Engine Plugin
# 功能：保存和恢复开发流程状态
#
# Review状态说明：
#   - current_review_passed: 当前状态是否通过reviewer (true/false)
#   - state_review_status: 各阶段review状态 {"REQUIREMENT": "PASS", "DESIGN": "FAIL", ...}
#===============================================================================

# 默认Checkpoint文件路径
DEFAULT_CHECKPOINT_FILE="recovery/checkpoint.json"
CHECKPOINT_FILE="${CHECKPOINT_FILE:-$DEFAULT_CHECKPOINT_FILE}"

# 检测jq是否可用
if command -v jq &> /dev/null; then
    HAS_JQ=true
else
    HAS_JQ=false
    echo "Warning: jq not found, using fallback grep/sed parsing" >&2
fi

#===============================================================================
# 函数：初始化checkpoint
#===============================================================================
checkpoint::init() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    # 确保recovery目录存在
    mkdir -p "$(dirname "$checkpoint_file")"

    cat > "$checkpoint_file" << EOF
{
  "state": "INIT",
  "current_task": "",
  "completed_tasks": [],
  "pending_tasks": [],
  "failed_tasks": [],
  "retry_count": 0,
  "current_review_passed": false,
  "state_review_status": {},
  "requirement_name": "",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "metadata": {}
}
EOF

    echo "Checkpoint已初始化: $checkpoint_file"
}

#===============================================================================
# 函数：读取checkpoint
#===============================================================================
checkpoint::read() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在: $checkpoint_file" >&2
        return 1
    fi

    cat "$checkpoint_file"
}

#===============================================================================
# 函数：获取checkpoint中的状态
#===============================================================================
checkpoint::get_state() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "INIT"
        return 1
    fi

    # 优先使用jq，fallback使用grep
    if [[ "$HAS_JQ" == "true" ]]; then
        jq -r '.state // "INIT"' "$checkpoint_file" 2>/dev/null || echo "INIT"
    else
        grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' "$checkpoint_file" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/' || echo "INIT"
    fi
}

#===============================================================================
# 函数：更新checkpoint中的状态
#===============================================================================
checkpoint::update_state() {
    local new_state="$1"
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 优先使用jq，fallback使用sed
    if [[ "$HAS_JQ" == "true" ]]; then
        jq --arg state "$new_state" --arg time "$timestamp" \
            '.state = $state | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        sed -i "s/\"state\": \"[^\"]*\"/\"state\": \"$new_state\"/" "$checkpoint_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$checkpoint_file"
    fi

    echo "状态已更新: $new_state"
}

#===============================================================================
# 函数：更新当前任务
#===============================================================================
checkpoint::update_task() {
    local task_id="$1"
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    # 优先使用jq，fallback使用sed
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ "$HAS_JQ" == "true" ]]; then
        jq --arg task "$task_id" --arg time "$timestamp" \
            '.current_task = $task | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        sed -i "s/\"current_task\": \"[^\"]*\"/\"current_task\": \"$task_id\"/" "$checkpoint_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$checkpoint_file"
    fi

    echo "当前任务已更新: $task_id"
}

#===============================================================================
# 函数：标记任务完成
#===============================================================================
checkpoint::mark_task_complete() {
    local task_id="$1"
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    # 优先使用jq，fallback使用sed
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ "$HAS_JQ" == "true" ]]; then
        jq --arg task "$task_id" --arg time "$timestamp" \
            '.current_task = "" | .completed_tasks += [$task] | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        # fallback: 使用sed更新（不支持数组操作，仅清空current_task）
        sed -i "s/\"current_task\": \"[^\"]*\"/\"current_task\": \"\"/" "$checkpoint_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$checkpoint_file"
    fi

    echo "任务已标记完成: $task_id"
}

#===============================================================================
# 函数：获取未完成任务列表
#===============================================================================
checkpoint::get_pending_tasks() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "[]"
        return 1
    fi

    if [[ "$HAS_JQ" == "true" ]]; then
        jq -r '.pending_tasks // [] | if type == "array" then . else [] end' "$checkpoint_file" 2>/dev/null || echo "[]"
    else
        # fallback: 返回空
        echo "[]"
    fi
}

#===============================================================================
# 函数：初始化任务列表（从tasks-list.md读取）
#===============================================================================
checkpoint::init_task_list() {
    local project_dir="${1:-$(pwd)}"
    local tasks_file="$project_dir/tasks/tasks-list.md"

    if [[ ! -f "$tasks_file" ]]; then
        echo "ERROR: 任务列表文件不存在: $tasks_file" >&2
        return 1
    fi

    # 提取所有任务编号（从表格中）
    local task_ids
    task_ids=$(grep -E '^\|[ ]*T[0-9]+' "$tasks_file" | grep -oE 'T[0-9]+' | sort -u)

    if [[ -z "$task_ids" ]]; then
        echo "WARNING: 未找到任务编号" >&2
        return 1
    fi

    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 构建JSON数组
    local json_array="["
    local first=true
    for task_id in $task_ids; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_array+=","
        fi
        json_array+="\"$task_id\""
    done
    json_array+="]"

    if [[ "$HAS_JQ" == "true" ]]; then
        jq --argjson tasks "$json_array" --arg time "$timestamp" \
            '.pending_tasks = $tasks | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    fi

    echo "已初始化任务列表: $json_array"
}

#===============================================================================
# 函数：标记任务为进行中（从pending移到current）
#===============================================================================
checkpoint::start_task() {
    local task_id="$1"
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$HAS_JQ" == "true" ]]; then
        jq --arg task "$task_id" --arg time "$timestamp" \
            '.current_task = $task | .pending_tasks = [.pending_tasks[] | select(. != $task)] | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        # fallback: 仅更新current_task
        sed -i "s/\"current_task\": \"[^\"]*\"/\"current_task\": \"$task_id\"/" "$checkpoint_file"
    fi

    echo "任务已开始: $task_id"
}

#===============================================================================
# 函数：标记任务失败（移回pending）
#===============================================================================
checkpoint::mark_task_failed() {
    local task_id="$1"
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$HAS_JQ" == "true" ]]; then
        jq --arg task "$task_id" --arg time "$timestamp" \
            '.current_task = "" | .failed_tasks += [$task] | .pending_tasks += [$task] | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        # fallback: 仅清空current_task
        sed -i "s/\"current_task\": \"[^\"]*\"/\"current_task\": \"\"/" "$checkpoint_file"
    fi

    echo "任务已标记失败: $task_id"
}

#===============================================================================
# 函数：增加重试计数
#===============================================================================
checkpoint::increment_retry() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    # 优先使用jq，fallback使用grep
    local current
    if [[ "$HAS_JQ" == "true" ]]; then
        current=$(jq -r '.retry_count // 0' "$checkpoint_file" 2>/dev/null || echo "0")
    else
        current=$(grep -o '"retry_count": [0-9]*' "$checkpoint_file" 2>/dev/null | grep -o '[0-9]*' || echo "0")
    fi
    local next=$((current + 1))

    # 更新retry_count和updated_at
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ "$HAS_JQ" == "true" ]]; then
        jq --argjson count "$next" --arg time "$timestamp" \
            '.retry_count = $count | .updated_at = $time' "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        sed -i "s/\"retry_count\": $current/\"retry_count\": $next/" "$checkpoint_file"
        sed -i "s/\"updated_at\": \"[^\"]*\"/\"updated_at\": \"$timestamp\"/" "$checkpoint_file"
    fi

    echo "重试计数: $next"
}

#===============================================================================
# 函数：重置checkpoint
#===============================================================================
checkpoint::reset() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ -f "$checkpoint_file" ]]; then
        rm "$checkpoint_file"
    fi

    checkpoint::init "$project_dir"
}

#===============================================================================
# 函数：设置当前状态review结果
#===============================================================================
checkpoint::set_review_passed() {
    local passed="$1"  # true 或 false
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "ERROR: Checkpoint文件不存在" >&2
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 获取当前状态
    local current_state
    current_state=$(checkpoint::get_state "$project_dir")

    if [[ "$HAS_JQ" == "true" ]]; then
        # 更新current_review_passed并更新state_review_status
        jq --arg state "$current_state" --arg passed "$passed" --arg time "$timestamp" \
            '.current_review_passed = ($passed == "true") | .state_review_status[$state] = $passed | .updated_at = $time' \
            "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    else
        # fallback: 仅更新current_review_passed
        if [[ "$passed" == "true" ]]; then
            sed -i 's/"current_review_passed": false/"current_review_passed": true/' "$checkpoint_file"
        fi
    fi

    echo "Review状态已更新: current_review_passed=$passed"
}

#===============================================================================
# 函数：获取当前状态review是否通过
#===============================================================================
checkpoint::is_review_passed() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "false"
        return 1
    fi

    if [[ "$HAS_JQ" == "true" ]]; then
        jq -r '.current_review_passed // false' "$checkpoint_file" 2>/dev/null
    else
        if grep -q '"current_review_passed": true' "$checkpoint_file" 2>/dev/null; then
            echo "true"
        else
            echo "false"
        fi
    fi
}

#===============================================================================
# 函数：获取指定状态的review状态
#===============================================================================
checkpoint::get_state_review_status() {
    local state="$1"
    local project_dir="${2:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo ""
        return 1
    fi

    if [[ "$HAS_JQ" == "true" ]]; then
        jq -r ".state_review_status.\"$state\" // \"\"" "$checkpoint_file" 2>/dev/null
    else
        echo ""
    fi
}

#===============================================================================
# 函数：推进状态时重置review状态
#===============================================================================
checkpoint::advance_state_with_review() {
    local new_state="$1"
    local project_dir="${2:-$(pwd)}"

    # 先推进状态
    checkpoint::update_state "$new_state" "$project_dir"

    # 重置当前状态的review为false
    if [[ "$HAS_JQ" == "true" ]]; then
        local checkpoint_file="$project_dir/$CHECKPOINT_FILE"
        local timestamp
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        jq --arg time "$timestamp" \
            '.current_review_passed = false | .updated_at = $time' \
            "$checkpoint_file" > "${checkpoint_file}.tmp" && \
            mv "${checkpoint_file}.tmp" "$checkpoint_file"
    fi

    echo "状态已推进到: $new_state, review状态已重置"
}

#===============================================================================
# 函数：检查是否可以从checkpoint恢复
#===============================================================================
checkpoint::can_recover() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    if [[ ! -f "$checkpoint_file" ]]; then
        return 1
    fi

    local state=$(checkpoint::get_state "$project_dir")
    if [[ "$state" == "INIT" || "$state" == "DONE" ]]; then
        return 1
    fi

    return 0
}

#===============================================================================
# 函数：打印checkpoint信息
#===============================================================================
checkpoint::print_info() {
    local project_dir="${1:-$(pwd)}"
    local checkpoint_file="$project_dir/$CHECKPOINT_FILE"

    echo "========================================"
    echo "  Checkpoint 信息"
    echo "========================================"

    if [[ ! -f "$checkpoint_file" ]]; then
        echo "Checkpoint文件不存在"
        echo "========================================"
        return
    fi

    local state=$(checkpoint::get_state "$project_dir")
    local current_task
    local completed_tasks
    local pending_tasks
    local failed_tasks
    local retry_count
    local updated_at
    local review_passed

    # 优先使用jq，fallback使用grep
    if [[ "$HAS_JQ" == "true" ]]; then
        current_task=$(jq -r '.current_task // ""' "$checkpoint_file" 2>/dev/null)
        completed_tasks=$(jq -r '.completed_tasks // [] | if type == "array" then join(", ") else . end' "$checkpoint_file" 2>/dev/null)
        pending_tasks=$(jq -r '.pending_tasks // [] | if type == "array" then join(", ") else . end' "$checkpoint_file" 2>/dev/null)
        failed_tasks=$(jq -r '.failed_tasks // [] | if type == "array" then join(", ") else . end' "$checkpoint_file" 2>/dev/null)
        retry_count=$(jq -r '.retry_count // 0' "$checkpoint_file" 2>/dev/null)
        updated_at=$(jq -r '.updated_at // ""' "$checkpoint_file" 2>/dev/null)
        review_passed=$(jq -r '.current_review_passed // false' "$checkpoint_file" 2>/dev/null)
    else
        current_task=$(grep -o '"current_task"[[:space:]]*:[[:space:]]*"[^"]*"' "$checkpoint_file" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/' || echo "")
        completed_tasks=$(grep -o '"completed_tasks"[[:space:]]*:\[[^]]*\]' "$checkpoint_file" 2>/dev/null | sed 's/.*: *\[ *\(.*\) *\]/\1/' || echo "")
        pending_tasks=""
        failed_tasks=""
        retry_count=$(grep -o '"retry_count": [0-9]*' "$checkpoint_file" 2>/dev/null | grep -o '[0-9]*' || echo "0")
        updated_at=$(grep -o '"updated_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$checkpoint_file" 2>/dev/null | sed 's/.*: *"\([^"]*\)"/\1/' || echo "")
        review_passed="false"
    fi

    echo "状态: $state"
    echo "当前Review: $([ "$review_passed" = "true" ] && echo "✓ 已通过" || echo "❌ 未通过")"
    echo "当前任务: ${current_task:-无}"
    echo "已完成任务: ${completed_tasks:-无}"
    echo "未完成任务: ${pending_tasks:-无}"
    echo "失败任务: ${failed_tasks:-无}"
    echo "重试计数: ${retry_count:-0}"
    echo "更新时间: ${updated_at:-未知}"
    echo "========================================"
}

#===============================================================================
# 导出函数（供其他脚本使用）
#===============================================================================
# 只在直接运行脚本时执行主逻辑
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Checkpoint 脚本 - State Engine Plugin"
    echo ""
    echo "可用函数:"
    echo "  checkpoint::init [project_dir]"
    echo "  checkpoint::read [project_dir]"
    echo "  checkpoint::get_state [project_dir]"
    echo "  checkpoint::update_state <state> [project_dir]"
    echo "  checkpoint::update_task <task_id> [project_dir]"
    echo "  checkpoint::mark_task_complete <task_id> [project_dir]"
    echo "  checkpoint::get_pending_tasks [project_dir]"
    echo "  checkpoint::init_task_list [project_dir]"
    echo "  checkpoint::start_task <task_id> [project_dir]"
    echo "  checkpoint::mark_task_failed <task_id> [project_dir]"
    echo "  checkpoint::increment_retry [project_dir]"
    echo "  checkpoint::reset [project_dir]"
    echo "  checkpoint::can_recover [project_dir]"
    echo "  checkpoint::print_info [project_dir]"
    echo "  checkpoint::set_review_passed <true|false> [project_dir]"
    echo "  checkpoint::is_review_passed [project_dir]"
    echo "  checkpoint::get_state_review_status <state> [project_dir]"
    echo "  checkpoint::advance_state_with_review <state> [project_dir]"
    echo ""
    echo "示例:"
    echo "  source scripts/checkpoint.sh"
    echo "  checkpoint::init"
    echo "  checkpoint::update_state REQUIREMENT"
    echo "  checkpoint::init_task_list"
    echo "  checkpoint::start_task T001"
    echo "  checkpoint::mark_task_complete T001"
fi