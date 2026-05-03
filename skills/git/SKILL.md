---
name: git
description: Git操作Skill - 自动化提交、分支管理、回滚
---

# Git Skill

Git操作Skill封装常用Git操作，支持自动化提交、分支管理和回滚。

## 功能

- **自动提交**：阶段完成时自动提交变更
- **分支管理**：创建和管理功能分支
- **变更回滚**：回退错误变更
- **变更查看**：查看历史变更

## 使用场景

### 1. 阶段完成提交

当使用 `using-e2e` 推进状态时，自动调用Git提交：

```bash
# 内部调用
git add requirements/ design/ testcase/ tasks/ execution/
git commit -m "feat: 完成需求分析阶段"
git tag "requirement-v1"
```

### 2. 创建功能分支

```
用户：开始开发用户管理模块
你：使用 git-skill 创建功能分支

[创建分支 feature/user-management]
[切换到新分支]
...
```

### 3. 回滚变更

```
用户：刚才的代码有严重问题，需要回滚
你：使用 git-skill 回滚最近一次提交

[回退最近一次提交]
[创建回滚分支 backup/rollback-xxx]
...
```

### 4. 查看变更历史

```
用户：看看最近做了什么变更
你：使用 git-skill 查看变更

[显示最近的提交历史]
[显示变更的文件统计]
```

## 命令参数

### 创建分支

```markdown
参数:
- branch_name: 分支名称（必需）
- base_branch: 基础分支（可选，默认为当前分支）
- create_backup: 是否创建备份分支（可选）

示例:
git::create-branch feature/new-feature main
```

### 提交变更

```markdown
参数:
- message: 提交信息（必需）
- path: 提交路径（可选，默认为变更的文件）

示例:
git::commit "feat: 完成用户认证模块"
```

### 回滚

```markdown
参数:
- target: 回滚目标（必需）
  - "HEAD~1" 或数字：回滚指定数量提交
  - commit hash：回滚到指定提交
- mode: 回滚模式（可选）
  - "soft"：软回滚（保留变更在暂存区）
  - "hard"：硬回滚（丢弃变更）

示例:
git::rollback "HEAD~1" "hard"
```

### 查看历史

```markdown
参数:
- limit: 显示数量（可选，默认为10）

示例:
git::log 20
```

## 提交信息规范

遵循 Conventional Commits：

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type类型

| Type | 说明 | 示例 |
|-----|------|-----|
| feat | 新功能 | feat(user): 增加用户注册 |
| fix | 修复Bug | fix(auth): 修复登录失败 |
| docs | 文档更新 | docs: 更新README |
| style | 格式调整 | style: 代码格式 |
| refactor | 重构 | refactor(auth): 重构认证逻辑 |
| test | 测试 | test: 增加单元测试 |
| chore | 其他 | chore: 更新依赖 |

### 示例

```
feat(requirement): 完成用户管理需求分析

- 识别核心用户故事4个
- 定义非功能需求
- 确认边界条件

Closes #123
```

## 与Using-E2E集成

`using-e2e` 在以下时机调用Git：

- 状态推进时（自动提交）
- 回滚时（创建备份分支）
- 分支切换时

## 注意事项

1. **先拉后推**：提交前先拉取最新代码
2. **有意义的提交**：每次提交要有清晰的变更说明
3. **备份优先**：回滚前先创建备份分支
4. **禁止强制**：除非必要，禁止强制推送