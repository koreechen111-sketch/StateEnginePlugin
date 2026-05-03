#!/usr/bin/env bash
#===============================================================================
# Checkpoint测试 - State Engine Plugin
# 功能：测试checkpoint脚本的正确性
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKPOINT_SCRIPT="$SCRIPT_DIR/scripts/checkpoint.sh"

# 加载checkpoint脚本
source "$CHECKPOINT_SCRIPT"

# 创建临时测试目录
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "========================================"
echo "  Checkpoint测试 - State Engine Plugin"
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

# 测试1: 初始化checkpoint
echo "测试1: 初始化checkpoint"
checkpoint::init "$TEST_DIR"
if [[ -f "$TEST_DIR/$CHECKPOINT_FILE" ]]; then
    echo "[PASS] checkpoint文件创建成功"
    ((TESTS_PASSED++))
else
    echo "[FAIL] checkpoint文件未创建"
    ((TESTS_FAILED++))
fi

# 测试2: 读取checkpoint
echo ""
echo "测试2: 读取checkpoint"
run_test "初始状态是INIT" "INIT" "$(checkpoint::get_state "$TEST_DIR")"

# 测试3: 更新状态
echo ""
echo "测试3: 更新状态"
checkpoint::update_state "REQUIREMENT" "$TEST_DIR"
run_test "状态更新为REQUIREMENT" "REQUIREMENT" "$(checkpoint::get_state "$TEST_DIR")"

checkpoint::update_state "DESIGN" "$TEST_DIR"
run_test "状态更新为DESIGN" "DESIGN" "$(checkpoint::get_state "$TEST_DIR")"

# 测试4: 更新任务
echo ""
echo "测试4: 更新任务"
checkpoint::update_task "T001" "$TEST_DIR"
local_task=$(grep -o '"current_task"[[:space:]]*:[[:space:]]*"[^"]*"' "$TEST_DIR/$CHECKPOINT_FILE" | sed 's/.*: *"\([^"]*\)"/\1/')
run_test "任务更新为T001" "T001" "$local_task"

# 测试5: 重试计数
echo ""
echo "测试5: 重试计数"
checkpoint::increment_retry "$TEST_DIR"
local_retry=$(grep -o '"retry_count": [0-9]*' "$TEST_DIR/$CHECKPOINT_FILE" | grep -o '[0-9]*')
run_test "重试计数为1" "1" "$local_retry"

checkpoint::increment_retry "$TEST_DIR"
local_retry=$(grep -o '"retry_count": [0-9]*' "$TEST_DIR/$CHECKPOINT_FILE" | grep -o '[0-9]*')
run_test "重试计数为2" "2" "$local_retry"

# 测试6: 检查恢复能力
echo ""
echo "测试6: 检查恢复能力"
if checkpoint::can_recover "$TEST_DIR"; then
    echo "[PASS] 可以从checkpoint恢复"
    ((TESTS_PASSED++))
else
    echo "[FAIL] 应该可以从checkpoint恢复"
    ((TESTS_FAILED++))
fi

# 测试7: 重置checkpoint
echo ""
echo "测试7: 重置checkpoint"
checkpoint::reset "$TEST_DIR"
run_test "重置后状态是INIT" "INIT" "$(checkpoint::get_state "$TEST_DIR")"

# 测试8: 打印信息
echo ""
echo "测试8: 打印checkpoint信息"
echo "输出:"
checkpoint::print_info "$TEST_DIR"

# 汇总结果
echo ""
echo "========================================"
echo "  测试结果汇总"
echo "========================================"
echo "通过: $TESTS_PASSED"
echo "失败: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ 所有测试通过!"
    exit 0
else
    echo "✗ 有测试失败"
    exit 1
fi