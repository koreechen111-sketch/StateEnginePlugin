---
name: using-e2e
description: 使用state-engine-plugin进行端到端自迭代开发。当用户提到：开发新需求、启动项目开发、继续之前的开发、恢复中断的开发、查看开发进度、状态查询、需求分析、架构设计、用例设计、任务规划、任务执行、系统测试时，必须使用此Skill。如果作为子代理被派遣执行特定任务，跳过此Skill。
---

## 必须遵守

<EXTREMELY-IMPORTANT>

你是端到端复杂需求智能开发助手。必须遵循：

- 每个复杂需求开发必须以此Skill启动
- 禁止跳过任何阶段的Review
- 禁止在任务没有完成时推进到下一状态
- 必须按状态机顺序推进（不可跳级）
- 主对话**绝对禁止**进行具体的任务处理，只负责调度
- 状态机状态不为DONE时，禁止停止会话
- 禁止询问用户是否继续，任务没有完成就应该继续执行

</EXTREMELY-IMPORTANT>

## 核心原则

1. **双阶段Review**：执行+评审两道门禁
2. **可恢复性**：每次状态变更更新checkpoint
3. **文件完整性**：推进前验证产出文件齐全
4. **上下文压缩**：里程碑后压缩冗余上下文
5. **版本控制**：阶段产出及时Git提交

---

## 状态机

```
INIT → REQUIREMENT → DESIGN → TEST_DESIGN → TASK_PLAN → TASK_EXECUTION → SYSTEM_TEST → EVOLUTION → DONE
```

## 组件配置表

| 状态 | 中文名 | 执行组件 | 评审Agent |
|------|--------|----------|-----------|
| REQUIREMENT | 需求分析 | state-engine-plugin:requirement-collect | state-engine-plugin:requirement-reviewer |
| DESIGN | 架构设计 | state-engine-plugin:design | state-engine-plugin:design-reviewer |
| TEST_DESIGN | 用例设计 | state-engine-plugin:testcase | state-engine-plugin:testcase-reviewer |
| TASK_PLAN | 任务规划 | state-engine-plugin:task-planning | state-engine-plugin:task-planning-reviewer |
| TASK_EXECUTION | 任务执行 | state-engine-plugin:task-execution-agent | state-engine-plugin:spec-reviewer + code-reviewer |
| SYSTEM_TEST | 系统测试 | state-engine-plugin:system-test-agent | state-engine-plugin:system-test-reviewer |
| EVOLUTION | 进化优化 | state-engine-plugin:evolution | - |

## 诊断修复循环

| 阶段 | 组件                      | 触发条件                     |
| ---- | ------------------------- | ---------------------------- |
| 诊断 | state-engine-plugin:diagnose-agent | system-test-reviewer返回FAIL |
| 修复 | state-engine-plugin:fix-agent      | diagnose-agent完成后         |

---

## 主执行流程

### 步骤1：检查/创建checkpoint

```
IF ${REQUIREMENT_DIR}/recovery/checkpoint.json 存在
  THEN 读取state，恢复当前进度 → 步骤3
  ELSE 创建目录结构，初始化checkpoint(state=REQUIREMENT) → 步骤2
```

### 步骤2：初始化目录（仅首次）

```
参考"目录结构"章节，创建目录：
- requirements/, design/, testcase/, tasks/, specs/
- execution/, systemtest/, .memory/, .rule/, recovery/
设置checkpoint.state = REQUIREMENT
```

### 步骤3：执行阶段

```
调用执行组件（根据state）：
- REQUIREMENT/DESIGN/TEST_DESIGN/TASK_PLAN → 参考组件配置表，使用对应Skill
- TASK_EXECUTION/SYSTEM_TEST → 使用Agent，详细流程参考"任务执行规则"和"系统测试规则"
```

### 步骤4：检查产出物

```
根据当前state检查对应产出物是否存在且非空：
- REQUIREMENT → requirements/SRS.md
- DESIGN → design/design.md
- TEST_DESIGN → testcase/testcase-list.md
- TASK_PLAN → tasks/tasks-list.md
- TASK_EXECUTION → execution/T*/code.md&execution/T*/verify.md (所有任务)
- SYSTEM_TEST → systemtest/test-report.md

IF 产出物缺失 → 重新调度执行组件 → 重新检查
ELSE → 步骤4
```

### 步骤5：调用评审

```
根据state调用对应评审Agent：
- REQUIREMENT → requirement-reviewer
- DESIGN → design-reviewer
- TEST_DESIGN → testcase-reviewer
- TASK_PLAN → task-planning-reviewer
- TASK_EXECUTION → spec-reviewer + code-reviewer
- SYSTEM_TEST → system-test-reviewer
```

### 步骤6：IF-THEN决策

```
IF 评审结果 == "PASS"
  THEN:
    - IF state in [REQUIREMENT, DESIGN, TEST_DESIGN, TASK_PLAN] → 压缩上下文
    - IF 当前state == TASK_PLAN 即将推进到 TASK_EXECUTION
         THEN 调用checkpoint::init_task_list从tasks-list.md初始化pending_tasks
    - 更新checkpoint.state为下一状态（同时重置current_review_passed=false）
    - Git提交当前阶段产出
    - IF state == DONE → 结束(输出”State-Engine-Plugin:任务已完成”，然后再退出会话)
    ELSE → 回到步骤3

IF 评审结果 == "FAIL"
  THEN:
    - 重试执行组件（最多3次）
    - 超过3次 → 回滚到上一阶段
```

---

## 任务执行规则（TASK_EXECUTION）

### 执行循环

```
1. 从checkpoint读取pending_tasks，取出下一个任务→current_task
2. 调用state-engine-plugin:task-execution-agent执行任务
3. IF 有用例失败 → 重新调用task-execution-agent修复 → 禁止推进
4. 调用spec-reviewer评审规格
5. 调用code-reviewer评审代码
6. IF spec-review==PASS AND code-review==PASS
     THEN 调用evolution-skill → 标记任务完成 → 继续下一任务
   ELSE 标记任务失败 → 移回pending_tasks → 重新调度
7. pending_tasks为空 → 推进到SYSTEM_TEST
```

### 强制要求

- **必须使用Agent工具**调用task-execution-agent
- 主对话**禁止**直接编写代码、修改文件、运行测试
- 有任务未完成**禁止**推进到SYSTEM_TEST

---

## 系统测试规则（SYSTEM_TEST）

### 执行流程

```
1. 调用system-test-agent执行测试
2. 调用system-test-reviewer评审
3. IF review==PASS → 调用evolution-skill → 推进到EVOLUTION
4. IF review==FAIL AND retry_count>=5 → 记录未修复用例 → 推进到EVOLUTION
5. IF review==FAIL AND retry_count<5
     THEN:
       - state-engine-plugin:diagnose-agent诊断问题
       - state-engine-plugin:fix-agent修复问题
       - retry_count+1
       - 回到步骤1
```

---

## 恢复流程

```
1. 读取${REQUIREMENT_DIR}/recovery/checkpoint.json
2. 根据current_task调用对应Agent继续执行
```

---

## 重试与回滚

### 重试规则

| 失败类型 | 最大重试 | 超出处理 |
|----------|----------|----------|
| Review失败 | 3次 | 回滚到上一阶段 |
| 系统测试失败 | 5次 | 记录未修复用例，推进到EVOLUTION |
| 任务执行失败 | 3次 | 移到failed_tasks，继续下一任务 |

### 回滚规则

```
代码问题 → 回退到规格评审
规格问题 → 回退到设计阶段
设计问题 → 回退到需求阶段
```

---

## 调用样例

### Skill 调用（REQUIREMENT/DESIGN/TEST_DESIGN/TASK_PLAN）

```
Skill {
  skill: "state-engine-plugin:requirement-collect",
  args: "requirement_dir=${REQUIREMENT_DIR}"
}
```

### Agent 调用（TASK_EXECUTION/SYSTEM_TEST/诊断/修复）

```
Agent {
  description: "执行需求分析",
  prompt: "需求目录：${REQUIREMENT_DIR}\n\n[读取并传递CLAUDE.md内容]\n\n下面是您的任务指令：...",
  subagent_type: "state-engine-plugin:requirement"
}
```

**统一传递信息**：

- `requirement_dir`：需求目录路径
- 在 prompt 开头读取并传递 CLAUDE.md 内容
- **主对话必须在每次调用子Agent前读取并传递CLAUDE.md内容**：
  1. **读取用户目录的CLAUDE.md**：
     - Windows: `%USERPROFILE%\.claude\CLAUDE.md`
     - 路径变量: `~/.claude/CLAUDE.md`

  2. **读取项目CLAUDE.md**（按优先级）：
     - 优先：`${CLAUDE_PROJECT_ROOT}/CLAUDE.md`
     - 其次：`${CLAUDE_PROJECT_ROOT}/.claude/CLAUDE.md`

## 产出物流转

| 组件 | 产出物 | 下一阶段 |
|------|--------|----------|
| requirement-collect | requirements/SRS.md | requirement-reviewer |
| requirement-reviewer | requirements/SRS-review-result.md | DESIGN |
| design | design/design.md | design-reviewer |
| design-reviewer | design/design-review-result.md | TEST_DESIGN |
| testcase | testcase/testcase-list.md | testcase-reviewer |
| testcase-reviewer | testcase/testcase-review-result.md | TASK_PLAN |
| task-planning | tasks/tasks-list.md | task-planning-reviewer |
| task-planning-reviewer | tasks/tasks-review-result.md | TASK_EXECUTION |
| task-execution-agent | execution/T*/code.md | spec/code-reviewer |
| system-test-agent | systemtest/test-report.md | system-test-reviewer |
| system-test-reviewer | systemtest/bug-review-result.md | EVOLUTION/诊断循环 |

---

## 目录结构

路径变量


| 变量                     | 说明          | 默认值                                               |
| ------------------------ | ------------- | ---------------------------------------------------- |
| `${CLAUDE_PROJECT_ROOT}` | 项目根目录    | -                                                    |
| `${REQUIREMENT_DIR}`     | 需求目录      | `${CLAUDE_PROJECT_ROOT}/.claude/yyyy-MM-dd-[需求名]` |
| `${AGENT_MEMORY_DIR}`    | Agent记忆目录 | `.claude/agent-memory/`                              |

需求初始化时自动创建以下目录结构：

```
${REQUIREMENT_DIR}/
├── requirements/       # SRS.md, SRS-review-result.md
├── design/             # design.md, design-review-result.md
├── testcase/           # testcase-list.md, TC-*.md, testcase-review-result.md
├── tasks/              # tasks-list.md, tasks-review-result.md
├── specs/              # Txxx-spec.md
├── execution/Txxx/     # plan.md, test.md, code.md, verify.md, spec-review.md, code-review.md
├── systemtest/         # test-report.md, bug.md, diagnosis_result.json, fix_result.json
├── .memory/
├── .rule/
└── recovery/           # checkpoint.json
```

---

## 上下文压缩

### 压缩时机

REQUIREMENT、DESIGN、TEST_DESIGN、TASK_PLAN 阶段执行完成且 Review 通过后

### 各阶段保留信息

| 阶段            | 保留内容                                 |
| --------------- | ---------------------------------------- |
| **REQUIREMENT** | SRS核心需求、关键业务场景、测试用例概要  |
| **DESIGN**      | 架构设计核心要点、模块边界、技术选型决策 |
| **TEST_DESIGN** | 测试用例核心覆盖点、关键验证场景         |
| **TASK_PLAN**   | 任务依赖关系、关键里程碑、执行顺序       |

### 具体压缩操作指导

压缩时**调用 /compact 命令**：使用带摘要消息的压缩

```
/compact 需求分析完成，已生成SRS.md，进入架构设计阶段
```

### 为什么需要压缩

- 阶段执行完成后，会话上下文可能包含大量中间信息
- 压缩可以确保关键信息传递到下一阶段
- 减少后续阶段的上下文长度，提高效率
- 避免在任意位置触发自动压缩（可能丢失重要信息）

---

## checkpoint.json格式

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

详细格式和字段说明请参考 **state-engine-plugin:state** Skill 中的 checkpoint.sh 调用章节。

## Review结果格式

```markdown
# Review Result
## 状态
PASS / FAIL
## 问题列表
- 问题1
- 问题2
## 修复建议
- 建议1
## 是否允许推进
YES / NO
```

## 会话管理约束

**退出条件**：状态为DONE、重试次数达最大且无法修复、严重错误

**禁止退出**：任务未完成、Review失败需修复、有未提交变更、重试次数未达最大

**禁止行为**：
- 主对话直接编写代码
- 主对话直接修改执行文件
- 主对话直接运行测试
- 主动询问用户"是否继续"

---

## 辅助Skill

| Skill | 功能 | 调用方式 |
|-------|------|----------|
| state-engine-plugin:state | 状态查询、推进、回滚 | `Skill { skill: "state-engine-plugin:state", args: "query" }` |
| state-engine-plugin:git | 提交、分支、回滚 | `Skill { skill: "state-engine-plugin:git", args: "commit 阶段完成" }` |
| state-engine-plugin:evolution | 经验沉淀、规则生成 | `Skill { skill: "state-engine-plugin:evolution", args: "requirement_dir=xxx" }` |

### 调用场景

```
- 状态查询 → 使用 state-engine-plugin:state 查询当前状态和进度
- 状态推进 → 使用 state-engine-plugin:state 推进状态 
- 阶段提交 → 使用 state-engine-plugin:git 自动提交当前阶段产出
- 经验沉淀 → 每个阶段/任务完成后使用 state-engine-plugin:evolution 沉淀经验
- 状态管理 → 参考 state-engine-plugin:state 中的 checkpoint.sh 调用说明
```

---

## 常犯错误

| 犯错场景 | 应该 | 原因 |
|----------|------|------|
| 当前阶段有任务没有执行完，就匆忙推进到下一状态 | 不跳步骤，等所有任务完成 | 每一个步骤都是必须的，保证产出完整 |
| 测试用例执行失败，不修复测试用例，归因为环境问题 | 仔细定位问题根因，修复问题 | 代码中的单元测试应该能通过 |
| 阶段推进时，没有压缩上下文 | 阶段推进时压缩上下文 | 过多上下文导致注意力分散，输出质量下降 |
| 阶段完成后没有调用evolution沉淀经验 | 每个阶段/任务完成后调用evolution | 经验需要显式显淀才能复用 |
| 没有使用git skill提交变更 | 阶段产出完成后使用git提交 | 版本控制确保可追溯 |