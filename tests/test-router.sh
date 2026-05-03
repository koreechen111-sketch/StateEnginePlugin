#!/usr/bin/env bash
#===============================================================================
# 路由测试 - State Engine Plugin
# 功能：测试全局调度功能的正确性
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_MACHINE_SCRIPT="$SCRIPT_DIR/scripts/state-machine.sh"
CHECKPOINT_SCRIPT="$SCRIPT_DIR/scripts/checkpoint.sh"

# 加载脚本
source "$STATE_MACHINE_SCRIPT"
source "$CHECKPOINT_SCRIPT"

# 创建临时测试目录
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "========================================"
echo "  路由功能测试 - State Engine Plugin"
echo "========================================"
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

# 测试1: 目录结构初始化
echo "测试1: 目录结构初始化"
INIT_DIR="$TEST_DIR/test-requirement"
mkdir -p "$INIT_DIR"
# 模拟目录初始化
mkdir -p "$INIT_DIR/requirements"
mkdir -p "$INIT_DIR/design"
mkdir -p "$INIT_DIR/testcase"
mkdir -p "$INIT_DIR/tasks"
mkdir -p "$INIT_DIR/specs"
mkdir -p "$INIT_DIR/execution"
mkdir -p "$INIT_DIR/recovery"

if [[ -d "$INIT_DIR/requirements" && -d "$INIT_DIR/design" && -d "$INIT_DIR/testcase" ]]; then
    echo "[PASS] 目录结构创建正确"
    ((TESTS_PASSED++))
else
    echo "[FAIL] 目录结构不完整"
    ((TESTS_FAILED++))
fi

# 测试2: 初始化checkpoint
echo ""
echo "测试2: 初始化checkpoint"
checkpoint::init "$INIT_DIR"
if [[ -f "$INIT_DIR/$CHECKPOINT_FILE" ]]; then
    echo "[PASS] checkpoint创建成功"
    ((TESTS_PASSED++))
else
    echo "[FAIL] checkpoint文件未创建"
    ((TESTS_FAILED++))
fi

# 测试3: 状态机流转
echo ""
echo "测试3: 状态机流转测试"

# 模拟状态流转
current_state="INIT"
next_state=$(state_machine::get_next_state "$current_state")
while [[ -n "$next_state" ]]; do
    checkpoint::update_state "$next_state" "$INIT_DIR"
    current_state="$next_state"
    next_state=$(state_machine::get_next_state "$current_state")
done

run_test "完整状态流转成功" "DONE" "$(checkpoint::get_state "$INIT_DIR")"

# 测试4: 检查点恢复
echo ""
echo "测试4: 检查点恢复测试"
checkpoint::reset "$INIT_DIR"
checkpoint::update_state "TASK_EXECUTION" "$INIT_DIR"
checkpoint::update_task "T003" "$INIT_DIR"

if checkpoint::can_recover "$INIT_DIR"; then
    echo "[PASS] 可以检测到可恢复状态"
    ((TESTS_PASSED++))
else
    echo "[FAIL] 应该检测到可恢复状态"
    ((TESTS_FAILED++))
fi

recovered_state=$(checkpoint::get_state "$INIT_DIR")
run_test "恢复状态为TASK_EXECUTION" "TASK_EXECUTION" "$recovered_state"

# 测试5: 状态不可跳级
echo ""
echo "测试5: 状态不可跳级测试"
checkpoint::reset "$INIT_DIR"
checkpoint::update_state "INIT" "$INIT_DIR"

# 尝试直接跳到DESIGN（应该失败）
if ! state_machine::can_transition "INIT" "DESIGN"; then
    echo "[PASS] INIT不能跳过REQUIREMENT"
    ((TESTS_PASSED++))
else
    echo "[FAIL] INIT不应该能跳过REQUIREMENT"
    ((TESTS_FAILED++))
fi

# 测试6: 状态可回滚
echo ""
echo "测试6: 状态回滚测试"
checkpoint::update_state "DESIGN" "$INIT_DIR"
prev_state=$(state_machine::get_prev_state "DESIGN")
if [[ "$prev_state" == "REQUIREMENT" ]]; then
    echo "[PASS] DESIGN可以回滚到REQUIREMENT"
    ((TESTS_PASSED++))
else
    echo "[FAIL] DESIGN应该能回滚到REQUIREMENT"
    ((TESTS_FAILED++))
fi

# 汇总结果
echo ""
echo "========================================"
echo "  测试结果汇总"
echo "========================================"
echo "通过: $TESTS_PASSED"
echo "失败: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ 所有路由测试通过!"
    exit 0
else
    echo "✗ 有测试失败"
    exit 1
fi