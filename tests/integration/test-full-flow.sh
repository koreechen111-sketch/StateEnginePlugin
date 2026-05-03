#!/usr/bin/env bash
#===============================================================================
# 集成测试 - State Engine Plugin
# 功能：测试完整流程的集成测试
#===============================================================================

# 使用固定的state-engine-plugin路径
STATE_ENGINE_PLUGIN_DIR="/d/01project/e2e-agent/state-engine-plugin"
SCRIPT_DIR="$STATE_ENGINE_PLUGIN_DIR/scripts"
STATE_MACHINE_SCRIPT="$SCRIPT_DIR/state-machine.sh"
CHECKPOINT_SCRIPT="$SCRIPT_DIR/checkpoint.sh"

# 加载脚本
source "$STATE_MACHINE_SCRIPT"
source "$CHECKPOINT_SCRIPT"

# 创建临时测试目录
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "========================================"
echo "  完整流程集成测试 - State Engine Plugin"
echo "========================================"
echo "测试目录: $TEST_DIR"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# 测试辅助函数
run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$expected" == "$actual" ]]; then
        echo "[PASS] $test_name"
        ((TESTS_PASSED++))
    else
        echo "[FAIL] $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        ((TESTS_FAILED++))
    fi
}

# ============================================
# 场景1: 新项目启动流程
# ============================================
echo "========================================"
echo "  场景1: 新项目启动流程"
echo "========================================"

PROJECT_DIR="$TEST_DIR/new-project"
mkdir -p "$PROJECT_DIR"

echo "步骤1: 初始化项目目录"
mkdir -p "$PROJECT_DIR/requirements"
mkdir -p "$PROJECT_DIR/design"
mkdir -p "$PROJECT_DIR/testcase"
mkdir -p "$PROJECT_DIR/tasks"
mkdir -p "$PROJECT_DIR/specs"
mkdir -p "$PROJECT_DIR/execution"
mkdir -p "$PROJECT_DIR/recovery"

run_test "需求目录创建" "true" "$([[ -d "$PROJECT_DIR/requirements" ]] && echo 'true')"
run_test "设计目录创建" "true" "$([[ -d "$PROJECT_DIR/design" ]] && echo 'true')"
run_test "用例目录创建" "true" "$([[ -d "$PROJECT_DIR/testcase" ]] && echo 'true')"
run_test "任务目录创建" "true" "$([[ -d "$PROJECT_DIR/tasks" ]] && echo 'true')"
run_test "规格目录创建" "true" "$([[ -d "$PROJECT_DIR/specs" ]] && echo 'true')"
run_test "执行目录创建" "true" "$([[ -d "$PROJECT_DIR/execution" ]] && echo 'true')"
run_test "恢复目录创建" "true" "$([[ -d "$PROJECT_DIR/recovery" ]] && echo 'true')"

echo ""
echo "步骤2: 初始化checkpoint"
checkpoint::init "$PROJECT_DIR"
run_test "checkpoint文件创建" "true" "$([[ -f "$PROJECT_DIR/$CHECKPOINT_FILE" ]] && echo 'true')"
run_test "初始状态为INIT" "INIT" "$(checkpoint::get_state "$PROJECT_DIR")"

echo ""
echo "步骤3: 推进到REQUIREMENT状态"
checkpoint::update_state "REQUIREMENT" "$PROJECT_DIR"
run_test "状态更新为REQUIREMENT" "REQUIREMENT" "$(checkpoint::get_state "$PROJECT_DIR")"

echo ""
echo "步骤4: 模拟需求阶段完成"
# 模拟创建SRS文档
cat > "$PROJECT_DIR/requirements/SRS.md" << 'EOF'
# 软件需求规格说明

## 1. 项目概述
项目名称: 测试项目
EOF

# 模拟需求评审
cat > "$PROJECT_DIR/requirements/SRS-review-result.md" << 'EOF'
# Review Result
## 状态
PASS
## 是否允许推进
YES
EOF

checkpoint::update_state "DESIGN" "$PROJECT_DIR"
run_test "状态推进到DESIGN" "DESIGN" "$(checkpoint::get_state "$PROJECT_DIR")"

# ============================================
# 场景2: 中断恢复流程
# ============================================
echo ""
echo "========================================"
echo "  场景2: 中断恢复流程"
echo "========================================"

# 设置中断点状态
checkpoint::update_state "TASK_EXECUTION" "$PROJECT_DIR"
checkpoint::update_task "T003" "$PROJECT_DIR"
checkpoint::increment_retry "$PROJECT_DIR"

current_state=$(checkpoint::get_state "$PROJECT_DIR")
current_task=$(grep -o '"current_task"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_DIR/$CHECKPOINT_FILE" | sed 's/.*: *"\([^"]*\)"/\1/')

echo "当前状态: $current_state"
echo "当前任务: $current_task"

run_test "可恢复状态检测" "true" "$(checkpoint::can_recover "$PROJECT_DIR" && echo 'true')"
run_test "当前状态为TASK_EXECUTION" "TASK_EXECUTION" "$current_state"

# ============================================
# 场景3: 完整状态流转
# ============================================
echo ""
echo "========================================"
echo "  场景3: 完整状态流转测试"
echo "========================================"

# 重置并测试完整流转
checkpoint::reset "$PROJECT_DIR"

STATES=("INIT" "REQUIREMENT" "DESIGN" "TEST_DESIGN" "TASK_PLAN" "TASK_EXECUTION" "SYSTEM_TEST" "EVOLUTION" "DONE")

for state in "${STATES[@]}"; do
    checkpoint::update_state "$state" "$PROJECT_DIR"
    current=$(checkpoint::get_state "$PROJECT_DIR")
    run_test "状态流转: $state" "$state" "$current"
done

# ============================================
# 场景4: 状态机边界测试
# ============================================
echo ""
echo "========================================"
echo "  场景4: 状态机边界测试"
echo "========================================"

checkpoint::reset "$PROJECT_DIR"

echo "测试INIT状态"
prev=$(state_machine::get_prev_state "INIT")
next=$(state_machine::get_next_state "INIT")
run_test "INIT是第一个状态" "" "$prev"
run_test "INIT的下一个是REQUIREMENT" "REQUIREMENT" "$next"

echo "测试DONE状态"
checkpoint::update_state "DONE" "$PROJECT_DIR"
next=$(state_machine::get_next_state "DONE")
prev=$(state_machine::get_prev_state "DONE")
run_test "DONE没有下一个状态" "" "$next"
run_test "DONE可以回退到EVOLUTION" "EVOLUTION" "$prev"

# ============================================
# 场景5: 进度计算测试
# ============================================
echo ""
echo "========================================"
echo "  场景5: 进度计算测试"
echo "========================================"

checkpoint::reset "$PROJECT_DIR"

# 进度公式: (索引 - 1) * 100 / 7
# INIT(0) -> 0%, REQUIREMENT(1) -> 0%, DESIGN(2) -> 14%, TASK_EXECUTION(5) -> 57%, EVOLUTION(7) -> 85%, DONE(8) -> 100%
progress_states=("INIT" "REQUIREMENT" "DESIGN" "TEST_DESIGN" "TASK_PLAN" "TASK_EXECUTION" "SYSTEM_TEST" "EVOLUTION" "DONE")
expected_progress=(0 0 14 28 42 57 71 85 100)

for i in "${!progress_states[@]}"; do
    checkpoint::update_state "${progress_states[$i]}" "$PROJECT_DIR"
    actual=$(state_machine::get_progress "${progress_states[$i]}")
    expected=${expected_progress[$i]}
    run_test "${progress_states[$i]} 进度" "$expected" "$actual"
done

# 汇总结果
echo ""
echo "========================================"
echo "  集成测试结果汇总"
echo "========================================"
echo "通过: $TESTS_PASSED"
echo "失败: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ 所有集成测试通过!"
    exit 0
else
    echo "✗ 有测试失败"
    exit 1
fi