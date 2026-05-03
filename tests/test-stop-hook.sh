#!/usr/bin/env bash
#===============================================================================
# Stop Hook 测试 - State Engine Plugin
# 功能：测试 stop-hook 脚本的场景识别逻辑
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STOP_HOOK="$SCRIPT_DIR/hooks/stop-hook"

echo "========================================"
echo "  Stop Hook 测试 - State Engine Plugin"
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
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "[FAIL] $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# 创建临时测试目录
TEST_DIR=$(mktemp -d)
TEST_DIR2=$(mktemp -d)
TEST_DIR3=$(mktemp -d)

# 设置环境变量
export CLAUDE_PROJECT_ROOT="$TEST_DIR"

# 创建测试用的 transcript 文件
TRANSCRIPT_FILE="$TEST_DIR/transcript.jsonl"

# source stop-hook 脚本（只加载函数）
source "$STOP_HOOK" < /dev/null

echo "测试1: 查找需求目录 - 无需求目录"
# 测试 find_requirement_dir 无目录时返回空
result=$(dev_plugin_find_requirement_dir)
run_test "无需求目录时返回空" "" "$result"

echo ""
echo "测试2: 查找需求目录 - 有需求目录"
# 创建测试用需求目录
mkdir -p "$TEST_DIR/.claude/2026-03-25-test/recovery"
cat > "$TEST_DIR/.claude/2026-03-25-test/recovery/checkpoint.json" << 'EOF'
{
  "state": "TASK_EXECUTION",
  "current_task": "T001",
  "completed_tasks": [],
  "failed_tasks": [],
  "retry_count": 0,
  "requirement_name": "test",
  "updated_at": "2026-03-25T10:00:00Z"
}
EOF

result=$(dev_plugin_find_requirement_dir)
expected="$TEST_DIR/.claude/2026-03-25-test/recovery/checkpoint.json"
run_test "有需求目录时返回正确路径" "$expected" "$result"

echo ""
echo "测试3: 查找需求目录 - 多个需求目录取最新"
# 创建更新的需求目录
mkdir -p "$TEST_DIR/.claude/2026-03-26-new-feature/recovery"
cat > "$TEST_DIR/.claude/2026-03-26-new-feature/recovery/checkpoint.json" << 'EOF'
{
  "state": "DESIGN",
  "current_task": "",
  "completed_tasks": [],
  "failed_tasks": [],
  "retry_count": 0,
  "requirement_name": "new-feature",
  "updated_at": "2026-03-26T10:00:00Z"
}
EOF

result=$(dev_plugin_find_requirement_dir)
expected="$TEST_DIR/.claude/2026-03-26-new-feature/recovery/checkpoint.json"
run_test "多个需求目录取最新" "$expected" "$result"

echo ""
echo "测试4: 无活跃任务 - 无checkpoint"
# 重置环境，使用无checkpoint的目录
export CLAUDE_PROJECT_ROOT="$TEST_DIR2"
CHECKPOINT_FILE=$(dev_plugin_find_requirement_dir)
if ! dev_plugin_has_active_task; then
    echo "[PASS] 无checkpoint时has_active_task返回false"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 无checkpoint时has_active_task应返回false"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试5: 无活跃任务 - INIT状态"
# 创建INIT状态的checkpoint
mkdir -p "$TEST_DIR2/.claude/2026-03-25-test/recovery"
cat > "$TEST_DIR2/.claude/2026-03-25-test/recovery/checkpoint.json" << 'EOF'
{
  "state": "INIT",
  "current_task": "",
  "completed_tasks": [],
  "failed_tasks": [],
  "retry_count": 0,
  "requirement_name": "test",
  "updated_at": "2026-03-25T10:00:00Z"
}
EOF

export CLAUDE_PROJECT_ROOT="$TEST_DIR2"
CHECKPOINT_FILE=$(dev_plugin_find_requirement_dir)
if ! dev_plugin_has_active_task; then
    echo "[PASS] INIT状态时has_active_task返回false"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] INIT状态时has_active_task应返回false"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试6: 有活跃任务 - TASK_EXECUTION状态"
export CLAUDE_PROJECT_ROOT="$TEST_DIR"
CHECKPOINT_FILE=$(dev_plugin_find_requirement_dir)
if dev_plugin_has_active_task; then
    echo "[PASS] TASK_EXECUTION状态时has_active_task返回true"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] TASK_EXECUTION状态时has_active_task应返回true"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试7: 任务已完成 - DONE状态"
# 创建DONE状态的checkpoint
mkdir -p "$TEST_DIR3/.claude/2026-03-25-test/recovery"
cat > "$TEST_DIR3/.claude/2026-03-25-test/recovery/checkpoint.json" << 'EOF'
{
  "state": "DONE",
  "current_task": "",
  "completed_tasks": ["T001", "T002"],
  "failed_tasks": [],
  "retry_count": 0,
  "requirement_name": "test",
  "updated_at": "2026-03-25T12:00:00Z"
}
EOF

export CLAUDE_PROJECT_ROOT="$TEST_DIR3"
CHECKPOINT_FILE=$(dev_plugin_find_requirement_dir)
if dev_plugin_is_task_completed; then
    echo "[PASS] DONE状态时is_task_completed返回true"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] DONE状态时is_task_completed应返回true"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "========================================"
echo "  场景识别测试"
echo "========================================"
echo ""

# 测试需要用户反馈的场景
echo "测试8: 场景识别 - 需要用户反馈"

test_message="请确认是否需要修改代码？"
if dev_plugin_needs_user_feedback "$test_message"; then
    echo "[PASS] 检测到需要用户反馈"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到需要用户反馈"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_message="代码已经完成，你可以继续了"
if ! dev_plugin_needs_user_feedback "$test_message"; then
    echo "[PASS] 正常消息不应触发用户反馈"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 正常消息不应触发用户反馈"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_message="需要你反馈"
if dev_plugin_needs_user_feedback "$test_message"; then
    echo "[PASS] 检测到需要用户反馈"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 没有检测到需要用户反馈"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试9: 场景识别 - 询问是否继续"

test_message="是否继续执行？"
if dev_plugin_asks_continue "$test_message"; then
    echo "[PASS] 检测到询问是否继续"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到询问是否继续"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_message="Shall I continue?"
if dev_plugin_asks_continue "$test_message"; then
    echo "[PASS] 检测到英文continue"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到英文continue"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试10: 场景识别 - 测试失败"

test_message="测试失败了，需要修复"
if dev_plugin_tests_failed "$test_message"; then
    echo "[PASS] 检测到测试失败"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到测试失败"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_message="All tests passed"
if ! dev_plugin_tests_failed "$test_message"; then
    echo "[PASS] 测试通过不应触发失败"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 测试通过不应触发失败"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试11: 场景识别 - 所有测试通过"

test_message="所有测试通过"
if dev_plugin_all_tests_passed "$test_message"; then
    echo "[PASS] 检测到所有测试通过"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到所有测试通过"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试12: 场景识别 - Review未通过"

test_message="Review未通过，需要修改"
if dev_plugin_review_not_passed "$test_message"; then
    echo "[PASS] 检测到Review未通过"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到Review未通过"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试13: 场景识别 - 待办事项"

test_message="TODO: 完善错误处理"
if dev_plugin_has_pending_todos "$test_message"; then
    echo "[PASS] 检测到TODO"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到TODO"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_message="FIXME: 修复内存泄漏"
if dev_plugin_has_pending_todos "$test_message"; then
    echo "[PASS] 检测到FIXME"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到FIXME"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试14: 场景识别 - 需要外部依赖"

test_message="等待API响应"
if dev_plugin_needs_external_dependency "$test_message"; then
    echo "[PASS] 检测到需要外部依赖"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到需要外部依赖"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试15: 场景识别 - 正常结束"

test_message="Dev-Plugin:任务已完成"
if dev_plugin_is_normal_end "$test_message"; then
    echo "[PASS] 检测到正常结束"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到正常结束"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试16: 场景识别 - 严重错误"

test_message="发生致命错误，无法继续"
if dev_plugin_has_critical_error "$test_message"; then
    echo "[PASS] 检测到严重错误"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到严重错误"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试17: 场景识别 - 正在进行重构"

test_message="正在重构代码结构"
if dev_plugin_is_refactoring "$test_message"; then
    echo "[PASS] 检测到重构中"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到重构中"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo "测试18: 场景识别 - 用户明确退出"

test_message="可以了，退出吧"
if dev_plugin_user_explicit_exit "$test_message"; then
    echo "[PASS] 检测到用户明确退出"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 应检测到用户明确退出"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

test_message="任务未完成"
if ! dev_plugin_user_explicit_exit "$test_message"; then
    echo "[PASS] 未完成不应触发退出"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "[FAIL] 未完成不应触发退出"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# 清理
rm -rf "$TEST_DIR" "$TEST_DIR2" "$TEST_DIR3"

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