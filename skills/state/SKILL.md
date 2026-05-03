---
name: state
description: 在使用state-engine-plugin插件进行需求开发时，使用此Skill查询、推进、回滚状态机状态
---

# State Skill

状态操作Skill提供状态机的查询、推进和回滚功能。

## 功能

- **查询状态**：获取当前状态信息
- **推进状态**：推进到下一状态
- **回滚状态**：回退到之前的状态
- **获取进度**：获取开发进度百分比

## 使用示例

### 查询当前状态

```
用户：现在到什么阶段了？
你：使用 state-skill 查看状态

当前状态：TASK_EXECUTION
任务：T003
进度：60%
...
```

### 推进状态

```
用户：需求分析完成了，可以进入设计阶段
你：使用 state-skill 推进状态

[验证评审通过]
[更新checkpoint]
[推进到 DESIGN]
...
```

### 回滚状态

```
用户：发现需求有问题，需要回退到需求阶段
你：使用 state-skill 回滚到 REQUIREMENT

[回滚checkpoint]
[回滚文件]
[状态变为 REQUIREMENT]
...
```

## 命令参数

### 查看状态

```markdown
无参数

输出:
- 当前状态
- 状态名称（中文）
- 当前任务（如果有）
- 进度百分比
- 可执行的操作列表
```

### 推进状态

```markdown
参数:
- verify: 是否验证Review通过（可选，默认为true）

示例:
state::advance true

流程:
1. 检查是否可推进
2. 验证Review结果
3. 更新checkpoint
4. 更新状态
5. 输出新状态信息
```

### 回滚状态

```markdown
参数:
- target_state: 目标状态（可选，默认回退到上一个状态）

示例:
state::rollback REQUIREMENT

流程:
1. 检查是否可回滚
2. 创建备份
3. 回滚checkpoint
4. 回滚必要文件
5. 输出回滚后的状态
```

### 获取进度

```markdown
无参数

输出: 0-100的进度百分比

计算公式:
(当前状态索引 - 1) / (总状态数 - 2) * 100
```

## 状态列表

| 索引 | 状态 | 中文名 | 说明 |
|-----|------|-------|------|
| 0 | INIT | 初始化 | 项目开始 |
| 1 | REQUIREMENT | 需求分析 | 需求收集和评审 |
| 2 | DESIGN | 架构设计 | 系统设计 |
| 3 | TEST_DESIGN | 用例设计 | 测试用例设计 |
| 4 | TASK_PLAN | 任务规划 | 任务分解 |
| 5 | TASK_EXECUTION | 任务执行 | 代码实现 |
| 6 | SYSTEM_TEST | 系统测试 | 集成测试 |
| 7 | EVOLUTION | 进化优化 | 错误分析和优化 |
| 8 | DONE | 完成 | 项目结束 |

## 任务状态管理

**任务状态统一由 checkpoint.json 管理**，不再在 task-list 中显示状态。

### checkpoint.json 任务状态字段

| 字段 | 说明 |
|------|------|
| current_task | 当前执行中的任务编号 |
| completed_tasks | 已完成的任务列表 |
| pending_tasks | 未完成的任务列表 |
| failed_tasks | 失败的任务列表 |

### 状态流转

```
pending_tasks → current_task → completed_tasks
                      ↓
                failed_tasks → (重试后回到pending_tasks)
```

## checkpoint.sh 调用

状态管理底层调用 `scripts/checkpoint.sh` 实现。

### 加载脚本

```bash
source scripts/checkpoint.sh
```

### 常用函数

| 函数 | 功能 | 调用时机 |
|------|------|----------|
| `checkpoint::init [dir]` | 初始化checkpoint | 首次启动 |
| `checkpoint::get_state [dir]` | 获取当前状态 | 任意时刻 |
| `checkpoint::update_state <state> [dir]` | 更新状态 | 阶段推进 |
| `checkpoint::init_task_list [dir]` | 从tasks-list.md初始化任务 | TASK_PLAN→TASK_EXECUTION |
| `checkpoint::start_task <task_id> [dir]` | 开始任务 | 任务执行开始 |
| `checkpoint::mark_task_complete <task_id> [dir]` | 标记任务完成 | 任务执行成功 |
| `checkpoint::mark_task_failed <task_id> [dir]` | 标记任务失败 | 任务执行失败 |
| `checkpoint::set_review_passed <true/false> [dir]` | 设置review状态 | 评审后 |
| `checkpoint::is_review_passed [dir]` | 检查review是否通过 | 决策前 |
| `checkpoint::get_state_review_status <state> [dir]` | 获取指定状态的review历史 | 调试 |
| `checkpoint::advance_state_with_review <state> [dir]` | 推进状态并重置review | 阶段推进 |
| `checkpoint::increment_retry [dir]` | 增加重试计数 | 重试时 |
| `checkpoint::print_info [dir]` | 打印checkpoint信息 | 调试/查询 |

### 使用示例

```bash
# 加载脚本
source scripts/checkpoint.sh

# 查询状态
state=$(checkpoint::get_state "$REQUIREMENT_DIR")

# 初始化任务列表（TASK_PLAN完成后）
checkpoint::init_task_list "$REQUIREMENT_DIR"

# 开始执行任务
checkpoint::start_task T001 "$REQUIREMENT_DIR"

# 任务完成后标记
checkpoint::mark_task_complete T001 "$REQUIREMENT_DIR"

# 任务失败标记
checkpoint::mark_task_failed T001 "$REQUIREMENT_DIR"

# 评审通过后设置状态
checkpoint::set_review_passed true "$REQUIREMENT_DIR"

# 检查当前是否通过review
if $(checkpoint::is_review_passed "$REQUIREMENT_DIR"); then
    echo "Review已通过"
fi

# 推进到下一状态（自动重置review为false）
checkpoint::advance_state_with_review DESIGN "$REQUIREMENT_DIR"

# 重试计数
checkpoint::increment_retry "$REQUIREMENT_DIR"

# 打印完整信息
checkpoint::print_info "$REQUIREMENT_DIR"
```

### checkpoint.json格式

```json
{
  "state": "TASK_EXECUTION",
  "current_task": "T003",
  "completed_tasks": ["T001"],
  "pending_tasks": ["T002", "T004"],
  "failed_tasks": [],
  "retry_count": 0,
  "current_review_passed": true,
  "state_review_status": {"REQUIREMENT": "PASS", "DESIGN": "PASS"},
  "systemtest_retry_count": 0,
  "failed_test_cases": [],
  "requirement_name": "需求名",
  "updated_at": "2026-04-10T00:00:00Z"
}
```

**Review状态字段**：
- `current_review_passed`: 当前状态是否通过reviewer (true/false)
- `state_review_status`: 各阶段review历史状态 {"REQUIREMENT": "PASS", "DESIGN": "FAIL", ...}

## 与Using-E2E集成

`using-e2e` Skill内部调用 `state` 进行状态管理：

- `state::get` - 获取当前状态
- `state::advance` - 推进状态
- `state::rollback` - 回滚状态
- `checkpoint::*` - 底层状态管理

## 注意事项

1. **Review门禁**：推进状态前必须确认Review通过（检查current_review_passed）
2. **文件完整性**：推进前必须确认输出文件齐全
3. **不可跳级**：只能推进到下一个状态，不能跳过
4. **可回滚**：可以回滚到任意之前的状态
5. **状态恢复**：每次状态变更更新checkpoint，确保开发过程可恢复