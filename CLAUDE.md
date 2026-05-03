# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指导。

## 项目概述

**state-engine-plugin** 是一个 Claude Code 插件，用于端到端自迭代软件开发。它实现了状态机工作流程，采用 PDCA（计划-执行-检查-优化）循环和 TDD（测试驱动开发）原则。

## 状态机

```
INIT → REQUIREMENT → DESIGN → TEST_DESIGN → TASK_PLAN → TASK_EXECUTION → SYSTEM_TEST → EVOLUTION → DONE
```

## 常用命令

### 测试
```bash
# 运行所有测试
bash tests/run-all-tests.sh

# 运行特定测试
bash tests/test-checkpoint.sh
bash tests/test-state-machine.sh
bash tests/test-router.sh
bash tests/test-stop-hook.sh

# 集成测试
bash tests/integration/test-full-flow.sh
```

### Checkpoint 管理
```bash
# 加载 checkpoint 函数
source scripts/checkpoint.sh

# 初始化 checkpoint
checkpoint::init [project_dir]

# 获取当前状态
checkpoint::get_state [project_dir]

# 更新状态
checkpoint::update_state <state> [project_dir]

# 推进状态并重置 review
checkpoint::advance_state_with_review <state> [project_dir]

# 打印 checkpoint 信息
checkpoint::print_info [project_dir]
```

## 架构

### 组件

| 组件 | 用途 | 文件 |
|------|------|------|
| **Skills** | 阶段特定逻辑（需求收集、设计、用例设计、任务规划、状态、Git、经验沉淀） | `skills/*/SKILL.md` |
| **Agents** | 复杂任务执行（任务执行Agent、诊断Agent、修复Agent、代码评审等） | `agents/*.md` |
| **Hooks** | 会话生命周期管理 | `hooks/*.cmd`, `hooks/session-start`, `hooks/stop-hook` |
| **Scripts** | 状态管理工具 | `scripts/checkpoint.sh`, `scripts/state-machine.sh` |

### 目录结构（按需求）

```
${REQUIREMENT_DIR}/
├── requirements/       # SRS.md, SRS-review-result.md
├── design/             # design.md, design-review-result.md
├── testcase/           # testcase-list.md, TC-*.md, testcase-review-result.md
├── tasks/              # tasks-list.md, tasks-review-result.md
├── specs/              # Txxx-spec.md（任务规格文档）
├── execution/Txxx/     # plan.md, test.md, code.md, verify.md, check.md, optimize.md
├── systemtest/         # test-report.md, diagnosis_result.json, fix_result.json
├── .memory/            # PROJECT.md（经验沉淀）
├── .rule/              # RULE.md（开发规则）
└── recovery/           # checkpoint.json（状态持久化）
```

### 状态转换规则

1. **Review 门禁**：推进状态前必须通过评审
2. **顺序执行**：不能跳过状态
3. **可恢复性**：所有状态变更都会更新 checkpoint.json
4. **重试限制**：评审最多 3 次，系统测试最多 5 次

### PDCA + TDD 工作流程

每个任务的执行遵循：
- **Plan（计划）** → 生成 `plan.md`
- **Do-Test（测试）** → 编写失败的测试，输出 `test.md`
- **Do-Code（编码）** → 实现最少的代码，输出 `code.md`
- **Do-Verify（验证）** → 运行测试直到通过，输出 `verify.md`
- **Check（检查）** → 验证验收标准，输出 `check.md`
- **Optimize（优化）** → 提升代码质量，输出 `optimize.md`

### checkpoint.json 字段

| 字段 | 说明 |
|------|------|
| `state` | 当前工作流状态 |
| `current_task` | 正在执行的任务 ID |
| `pending_tasks` | 待执行的任务列表 |
| `completed_tasks` | 已完成的任务列表 |
| `failed_tasks` | 需要重试的失败任务 |
| `current_review_passed` | 当前阶段是否通过评审 |
| `state_review_status` | 各状态的历史评审结果 |

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CLAUDE_PLUGIN_ROOT` | 插件根目录 | - |
| `REQUIREMENT_DIR` | 当前需求目录 | `.claude/yyyy-MM-dd-[需求名]` |
| `CLAUDE_PROJECT_ROOT` | 项目根目录 | 当前工作目录 |

## 关键模式

### 状态查询
使用 `state` skill 进行状态机查询、推进或回滚。

### 阶段转换
1. 执行阶段特定组件
2. 验证产出物是否存在
3. 调用评审 Agent
4. 如果 PASS：推进状态，提交产出物
5. 如果 FAIL：重试（最多 3 次）或回滚

### 上下文压缩
完成 REQUIREMENT、DESIGN、TEST_DESIGN 或 TASK_PLAN 阶段并通过评审后，使用 `/compact` 减少上下文后再继续。