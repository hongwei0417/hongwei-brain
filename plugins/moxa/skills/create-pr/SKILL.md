---
name: create-pr
allowed-tools: Bash(git:*), mcp__gitlab__create_merge_request, mcp__gitlab__get_project, AskUserQuestion
description: Create GitLab Merge Request with automatic fork detection. Handles both same-project MR and cross-project MR (fork to upstream) via GitLab MCP. Supports custom target branch selection. Triggers on "create pr", "create mr", "merge request", "submit pr", or "push and create pr".
---

# Create PR Skill (GitLab)

## Overview

Create GitLab Merge Request with automatic fork detection. Uses GitLab MCP for both same-project and cross-project (fork → upstream) MR creation. Allows custom target branch selection.

## When to Use

- Submitting changes for review
- Creating Merge Request from feature branch
- Pushing fork changes to upstream project

## Parameters (Optional)

This skill accepts the following optional parameters when invoked:

- **issue_tracker_base_url** — Issue tracker base URL (e.g. `https://myteam.atlassian.net`, `https://gitlab.com/group/project/-/issues`). When provided, extracted issue keys will be rendered as clickable links. If not provided and issue keys are found, the skill will ask the user for the URL.

## Process

### 1. Analyze Repository State

```bash
# Current branch
git branch --show-current

# Remote information
git remote -v

# Get upstream tracking branch (the branch current branch was created from)
git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "No upstream"

# Check for upstream remote (fork scenario)
git remote get-url upstream 2>/dev/null || echo "No upstream remote"
```

### 2. Detect Fork Scenario

**Check for fork scenario:**

```bash
# Get origin URL
ORIGIN_URL=$(git remote get-url origin)

# Check if upstream exists
UPSTREAM_URL=$(git remote get-url upstream 2>/dev/null)
```

**Scenario A: Same Project (No Fork)**
- Only `origin` remote exists
- Use `mcp__gitlab__create_merge_request` with `project_id` only

**Scenario B: Fork (origin → upstream)**
- Both `origin` and `upstream` remotes exist
- Use `mcp__gitlab__create_merge_request` with `project_id` (source) + `target_project_id` (upstream)

### 3. Collect MR Settings

**If fork detected, ask for target remote:**
```
偵測到 Fork 場景。請選擇 MR 目標 Remote：

1. origin (自己的專案)
2. upstream (原始專案)
```

**Ask for target branch:**

First, detect possible target branches:
```bash
# Get the branch this was created from
PARENT_BRANCH=$(git log --pretty=format:'%D' | grep -o 'origin/[^,)]*' | head -1 | sed 's|origin/||')

# List common target branches
git branch -r | grep -E 'origin/(main|master|develop)' | sed 's|origin/||'
```

Then ask user:
```
請選擇合併目標分支：

1. main
2. develop
3. <detected parent branch> (當前分支的來源)
4. 自訂輸入
```

### 4. Push Branch

Ensure branch is pushed to remote:

```bash
# Push with upstream tracking
git push -u origin $(git branch --show-current)
```

### 5. Generate MR Content

#### 5a. Gather Data

```bash
TARGET_BRANCH=<user selected target>
CURRENT_BRANCH=$(git branch --show-current)
MERGE_BASE=$(git merge-base origin/$TARGET_BRANCH $CURRENT_BRANCH)

# Commit messages for understanding changes
git log --no-merges --format='%h %s' $MERGE_BASE..$CURRENT_BRANCH

# Full commit bodies (may contain issue references or URLs)
git log --no-merges --format='%h %s%n%b' $MERGE_BASE..$CURRENT_BRANCH

# Diff for understanding scope and details
git diff $MERGE_BASE..$CURRENT_BRANCH
git diff --stat $MERGE_BASE..$CURRENT_BRANCH
```

#### 5b. Generate Title

- Single commit → use its message directly as title
- Multiple commits with same type/scope → synthesize (e.g. `feat(auth): add login and registration`)
- Multiple types → dominant type + general scope
- Keep under 70 characters

#### 5c. Extract Related Links

Scan all commit subjects and bodies for references:

1. **Full URLs** — Match any `https?://...` URLs directly (e.g. `https://gitlab.com/group/project/-/issues/42`)
2. **Issue keys** — Match patterns like `[A-Z]+-\d+` (e.g. `PROJ-123`), `#\d+` (e.g. `#42`)

Deduplicate all extracted references, then:

- Full URLs → use as-is
- Issue keys + `issue_tracker_base_url` provided → build links (e.g. `[PROJ-123](<base_url>/browse/PROJ-123)`)
- Issue keys found but no base URL → use AskUserQuestion to ask for the base URL
- No references found → omit the Related Issues section entirely

#### 5d. Generate Description

Analyze the diff content and commit messages, then generate the MR description using this template:

```markdown
## 📋 Summary

<!-- 1-2 sentence high-level overview of the MR purpose, generated from analyzing commits + diff -->

## ✨ Changes

<!-- Each bullet = one logical change, with a contextual emoji prefix.
     Derived from analyzing the actual diff content and commit messages.
     Group related changes together. Each bullet should be human-readable
     and explain WHAT changed and WHY, not just list file names. -->

- 🔐 加入使用者登入 API endpoint，支援 email/password 認證
- ✅ 新增登入流程的單元測試與整合測試
- 🗑️ 移除已棄用的舊版認證模組
- 📝 更新 API 文件，補充認證相關說明

## 🧪 Test Plan

- [ ] [Testing checklist items based on changes]

## 🔗 Related Issues

<!-- 從 commit messages 中自動擷取 issue references 和 URLs，無任何 references 則省略此區塊 -->
- [PROJ-123](https://myteam.atlassian.net/browse/PROJ-123)
- [#42](https://gitlab.com/group/project/-/issues/42)
- https://some-tracker.com/ticket/789
```

**Emoji 使用原則：**

| Emoji | 適用情境 |
|-------|---------|
| ✨ | 新功能 |
| 🐛 | Bug 修復 |
| ♻️ | 重構 |
| 🗑️ | 移除程式碼/檔案 |
| 📝 | 文件更新 |
| ✅ | 測試新增/修改 |
| 🔐 | 安全性/認證相關 |
| ⚡ | 效能改善 |
| 🎨 | UI/樣式調整 |
| 🔧 | 設定/配置變更 |
| 📦 | 依賴/套件變更 |
| 🏗️ | 架構調整 |

**Key design points:**
- **Summary** — 分析 diff + commits 後寫出 1-2 句概述，說明這個 MR 的整體目的
- **Changes** — 逐一分析每個邏輯改動，寫成人類可讀的 bullet point，每項搭配最適合的 emoji。描述改了什麼、為什麼改，而非列出檔案名稱
- **Related Issues** — 自動從 commits 擷取 issue keys（`PROJ-123`, `#42`）和完整 URLs，搭配 `issue_tracker_base_url` 產生連結；無任何 references 則省略此區塊

### 6. Extract Project Identifiers

**Extract project path from git remote URL:**

```bash
# Extract project path (supports both SSH and HTTPS URLs)
# git@gitlab.com:user/repo.git → user/repo
# https://gitlab.com/user/repo.git → user/repo
ORIGIN_PROJECT=$(git remote get-url origin | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's|\.git$||')
```

**For fork scenario, also extract upstream project path:**

```bash
UPSTREAM_PROJECT=$(git remote get-url upstream | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's|\.git$||')
```

**Resolve numeric project IDs using `mcp__gitlab__get_project`:**

For cross-project MR, call `mcp__gitlab__get_project` with the URL-encoded upstream project path to get its numeric `id`. This is needed for the `target_project_id` parameter.

### 7. Create MR via GitLab MCP

#### Scenario A: Same Project

Use `mcp__gitlab__create_merge_request`:

```
project_id: <origin project path, URL-encoded>
source_branch: <current branch>
target_branch: <user selected target branch>
title: <generated title>
description: <generated description>
```

#### Scenario B: Cross Project (Fork)

Use `mcp__gitlab__create_merge_request`:

```
project_id: <origin project path, URL-encoded (source/fork)>
target_project_id: <upstream numeric project ID from mcp__gitlab__get_project>
source_branch: <current branch>
target_branch: <user selected target branch>
title: <generated title>
description: <generated description>
```

### 8. Report Results

After MR creation, report:
- MR URL
- MR number
- Source branch
- Target branch
- Target remote (origin or upstream)

## Target Branch Selection

The skill supports flexible target branch selection:

| Scenario | Default Target | User Can Select |
|----------|---------------|-----------------|
| Feature branch | main | Any branch |
| Hotfix | main | production, main |
| Release | develop | main, release/* |
| From fork | upstream/main | Any upstream branch |

**Common patterns:**
- `feature/*` → `develop` or `main`
- `fix/*` → `main` or the branch it was created from
- `hotfix/*` → `main` and `production`
- `release/*` → `main`

## Error Handling

**MCP tool error:**
- Parse error message from MCP response
- Suggest common fixes (permissions, branch exists, etc.)

**No upstream remote for fork scenario:**
```
錯誤：找不到 upstream remote

如果這是 fork 專案，請先設定 upstream remote：
git remote add upstream <upstream-url>
```

## Examples

**Same Project MR to main:**
```
Branch: feature/add-auth
Target: main
Method: GitLab MCP (project_id only)
Result: !123 https://gitlab.com/user/repo/-/merge_requests/123
```

**Same Project MR to develop:**
```
Branch: feature/add-auth
Target: develop (user selected)
Method: GitLab MCP (project_id only)
Result: !124 https://gitlab.com/user/repo/-/merge_requests/124
```

**Cross-Project MR (Fork) to custom branch:**
```
Source: user/repo-fork (feature/add-auth)
Target: original/repo (release/v2.0)
Method: GitLab MCP (project_id + target_project_id)
Result: !456 https://gitlab.com/original/repo/-/merge_requests/456
```

## Integration Note

When called from `/git-flow`:
- Receives target remote and target branch settings from first phase
- Branch should already be created and pushed
- Reports MR URL as final workflow output
