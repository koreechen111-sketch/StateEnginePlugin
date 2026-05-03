#!/usr/bin/env bash
#===============================================================================
# 状态机脚本 - State Engine Plugin
# 功能：管理开发流程状态机的状态定义和转换
#
# 任务状态由 checkpoint.json 统一管理:
#   - current_task: 当前执行中的任务
#   - completed_tasks: 已完成的任务列表
#   - pending_tasks: 未完成的任务列表
#   - failed_tasks: 失败的任务列表
#===============================================================================

# 状态定义
declare -A STATE_NAMES
STATE_NAMES["INIT"]="初始化"
STATE_NAMES["REQUIREMENT"]="需求分析"
STATE_NAMES["DESIGN"]="架构设计"
STATE_NAMES["TEST_DESIGN"]="用例设计"
STATE_NAMES["TASK_PLAN"]="任务规划"
STATE_NAMES["TASK_EXECUTION"]="任务执行"
STATE_NAMES["SYSTEM_TEST"]="系统测试"
STATE_NAMES["EVOLUTION"]="进化优化"
STATE_NAMES["DONE"]="完成"

# 状态列表（按顺序）
STATE_ORDER=("INIT" "REQUIREMENT" "DESIGN" "TEST_DESIGN" "TASK_PLAN" "TASK_EXECUTION" "SYSTEM_TEST" "EVOLUTION" "DONE")

# 状态转换映射（当前状态 -> 下一个状态）
TRANSITIONS=(
    "INIT:REQUIREMENT"
    "REQUIREMENT:DESIGN"
    "DESIGN:TEST_DESIGN"
    "TEST_DESIGN:TASK_PLAN"
    "TASK_PLAN:TASK_EXECUTION"
    "TASK_EXECUTION:SYSTEM_TEST"
    "SYSTEM_TEST:EVOLUTION"
    "EVOLUTION:DONE"
)

#===============================================================================
# 函数：检查状态是否有效
#===============================================================================
state_machine::is_valid_state() {
    local state="$1"
    for s in "${STATE_ORDER[@]}"; do
        if [[ "$state" == "$s" ]]; then
            return 0
        fi
    done
    return 1
}

#===============================================================================
# 函数：获取下一个状态
#===============================================================================
state_machine::get_next_state() {
    local current_state="$1"
    local found=0

    for i in "${!STATE_ORDER[@]}"; do
        if [[ "${STATE_ORDER[$i]}" == "$current_state" ]]; then
            found=1
            if [[ $i -lt $((${#STATE_ORDER[@]} - 1)) ]]; then
                echo "${STATE_ORDER[$((i + 1))]}"
                return 0
            fi
            break
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "ERROR: 未知状态: $current_state" >&2
        return 1
    fi

    # 已经是最后一个状态
    echo ""  # 返回空字符串
    return 1
}

#===============================================================================
# 函数：获取上一个状态
#===============================================================================
state_machine::get_prev_state() {
    local current_state="$1"
    local found=0

    for i in "${!STATE_ORDER[@]}"; do
        if [[ "${STATE_ORDER[$i]}" == "$current_state" ]]; then
            found=1
            if [[ $i -gt 0 ]]; then
                echo "${STATE_ORDER[$((i - 1))]}"
                return 0
            fi
            break
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "ERROR: 未知状态: $current_state" >&2
        return 1
    fi

    # 已经是第一个状态
    echo ""  # 返回空字符串
    return 1
}

#===============================================================================
# 函数：检查是否可以转换到目标状态
#===============================================================================
state_machine::can_transition() {
    local from_state="$1"
    local to_state="$2"

    # 只能前进到下一个状态，或回退到任意之前的状态
    local from_index=-1
    local to_index=-1

    for i in "${!STATE_ORDER[@]}"; do
        if [[ "${STATE_ORDER[$i]}" == "$from_state" ]]; then
            from_index=$i
        fi
        if [[ "${STATE_ORDER[$i]}" == "$to_state" ]]; then
            to_index=$i
        fi
    done

    if [[ $from_index -eq -1 || $to_index -eq -1 ]]; then
        return 1
    fi

    # 前进（下一个状态）或回退（之前的状态）
    if [[ $to_index -eq $((from_index + 1)) ]] || [[ $to_index -lt $from_index ]]; then
        return 0
    fi

    return 1
}

#===============================================================================
# 函数：获取状态名称（中文）
#===============================================================================
state_machine::get_state_name() {
    local state="$1"
    if [[ -v STATE_NAMES[$state] ]]; then
        echo "${STATE_NAMES[$state]}"
    else
        echo "$state"
    fi
}

#===============================================================================
# 函数：获取所有状态
#===============================================================================
state_machine::get_all_states() {
    for state in "${STATE_ORDER[@]}"; do
        echo "$state"
    done
}

#===============================================================================
# 函数：获取状态进度
#===============================================================================
state_machine::get_progress() {
    local current_state="$1"
    local total=${#STATE_ORDER[@]}
    local current=0

    for i in "${!STATE_ORDER[@]}"; do
        if [[ "${STATE_ORDER[$i]}" == "$current_state" ]]; then
            current=$i
            break
        fi
    done

    # 计算百分比（排除INIT和DONE）
    local percentage=$(( (current - 1) * 100 / (total - 2) ))
    if [[ $percentage -lt 0 ]]; then
        percentage=0
    elif [[ $percentage -gt 100 ]]; then
        percentage=100
    fi

    echo "$percentage"
}

#===============================================================================
# 函数：打印状态机信息
#===============================================================================
state_machine::print_info() {
    local current_state="$1"
    echo "========================================"
    echo "  状态机信息"
    echo "========================================"
    echo "当前状态: $current_state ($(state_machine::get_state_name "$current_state"))"
    echo "进度: $(state_machine::get_progress "$current_state")%"
    echo ""
    echo "状态流转:"
    local prev_state=""
    for i in "${!STATE_ORDER[@]}"; do
        local state="${STATE_ORDER[$i]}"
        local prefix="  "
        if [[ "$state" == "$current_state" ]]; then
            prefix="  * "
        elif [[ -n "$prev_state" ]] && state_machine::can_transition "$prev_state" "$state"; then
            prefix="  ->"
        else
            prefix="   "
        fi
        echo "${prefix} ${state} ($(state_machine::get_state_name "$state"))"
        prev_state="$state"
    done
    echo "========================================"
}

#===============================================================================
# 导出函数（供其他脚本使用）
#===============================================================================
# 只在直接运行脚本时执行主逻辑
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "状态机脚本 -State Engine Plugin"
    echo ""
    echo "可用函数:"
    echo "  state_machine::is_valid_state <state>"
    echo "  state_machine::get_next_state <state>"
    echo "  state_machine::get_prev_state <state>"
    echo "  state_machine::can_transition <from> <to>"
    echo "  state_machine::get_state_name <state>"
    echo "  state_machine::get_all_states"
    echo "  state_machine::get_progress <state>"
    echo "  state_machine::print_info <state>"
    echo ""
    echo "示例: source scripts/state-machine.sh && state_machine::get_next_state INIT"
fi