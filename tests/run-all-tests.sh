#!/usr/bin/env bash
#===============================================================================
# 运行所有测试 - State Engine Plugin
# 功能：运行所有测试并输出汇总结果
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "  State Engine Plugin - 测试套件"
echo "========================================"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# 运行测试函数
run_test_suite() {
    local test_name="$1"
    local test_script="$2"

    echo "----------------------------------------"
    echo "  $test_name"
    echo "----------------------------------------"

    if [[ -f "$test_script" ]]; then
        bash "$test_script"
        local result=$?
        if [[ $result -eq 0 ]]; then
            echo "✓ $test_name 通过"
            ((TOTAL_PASSED++))
        else
            echo "✗ $test_name 失败"
            ((TOTAL_FAILED++))
        fi
    else
        echo "⚠ $test_name 脚本不存在"
        ((TOTAL_SKIPPED++))
    fi
    echo ""
}

# 测试1: 状态机测试
run_test_suite "状态机测试" "$SCRIPT_DIR/test-state-machine.sh"

# 测试2: Checkpoint测试
run_test_suite "Checkpoint测试" "$SCRIPT_DIR/test-checkpoint.sh"

# 测试3: 路由测试
run_test_suite "路由测试" "$SCRIPT_DIR/test-router.sh"

# 测试4: 集成测试
run_test_suite "集成测试" "$SCRIPT_DIR/integration/test-full-flow.sh"

# 汇总结果
echo "========================================"
echo "  测试套件汇总"
echo "========================================"
echo "通过: $TOTAL_PASSED"
echo "失败: $TOTAL_FAILED"
echo "跳过: $TOTAL_SKIPPED"
echo ""

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo "✓ 所有测试套件通过!"
    exit 0
else
    echo "✗ 有测试套件失败"
    exit 1
fi