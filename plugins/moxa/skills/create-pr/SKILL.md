---
name: create-pr
allowed-tools: Bash(git:*), Skill, mcp__gitlab__create_merge_request, mcp__gitlab__get_project, AskUserQuestion
description: Create GitLab Merge Request with automatic fork detection. Automatically runs create-branch and commit skills before MR creation — no confirmation needed for those steps. When an upstream remote exists, auto-detects the target branch (e.g. main → upstream/main, nos-v6.0-develop → upstream/nos-v6.0-develop) without asking. Triggers on "create pr", "create mr", "merge request", "submit pr", or "push and create pr".
---

# Create PR Skill (GitLab)

## Overview

End-to-end flow: **create-branch → commit → push → create MR**. The first two steps run automatically via their respective skills. MR target branch is auto-resolved when an `upstream` remote is detected.

## When to Use

- Submitting changes for review
- Creating Merge Request from feature branch
- Pushing fork changes to upstream project

## Parameters (Optional)

- **issue_tracker_base_url** — Issue tracker base URL (e.g. `https://myteam.atlassian.net`). When provided, extracted issue keys are rendered as clickable links. If not provided and issue keys are found, ask the user for the URL.

## Process

### 1. Pre-Flight: Branch and Commit

Execute these two steps automatically — do not ask for confirmation.

#### 1a. Ensure Feature Branch

Check the current branch:

```bash
git branch --show-current
```

If on a mainline branch (`main`, `master`, `develop`, or any branch matching `nos-v*/develop`, `nos-v*/main`), invoke the `moxa:create-branch` skill to create a feature branch. Pass it the context of current changes so it can generate an appropriate branch name.

If already on a feature/fix/refactor/etc. branch, skip this step.

#### 1b. Commit Uncommitted Changes

Check for uncommitted changes:

```bash
git status --porcelain
```

If there are staged or unstaged changes (non-empty output), invoke the `moxa:commit` skill to analyze and commit them. Pass along `issue_tracker_base_url` if provided.

If the working tree is clean (no changes), skip this step.

### 2. Analyze Repository State

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

### 3. Detect Fork and Resolve Target Branch

**Extract remote URLs:**

```bash
ORIGIN_URL=$(git remote get-url origin)
UPSTREAM_URL=$(git remote get-url upstream 2>/dev/null)
```

#### Scenario A: Fork Detected (upstream remote exists) — Auto-resolve

When both `origin` and `upstream` remotes exist, determine the target branch automatically:

1. **Find the base branch** — the branch the current feature branch was created from:
   ```bash
   # Method 1: Check tracking branch
   git rev-parse --abbrev-ref @{upstream} 2>/dev/null | sed 's|^origin/||'

   # Method 2: If no tracking, find nearest common ancestor with known branches
   git branch -r --list 'origin/*' | sed 's|origin/||' | while read branch; do
     echo "$(git merge-base --octopus HEAD origin/$branch 2>/dev/null | head -c 8) $branch"
   done | sort -rn | head -5
   ```

2. **Map to upstream target** — the base branch name maps directly:
   - `main` → target `main` on upstream
   - `nos-v6.0-develop` → target `nos-v6.0-develop` on upstream
   - `develop` → target `develop` on upstream

3. **Verify the target branch exists on upstream:**
   ```bash
   git ls-remote --heads upstream <target_branch>
   ```
   If it does not exist, fall back to asking the user.

4. **Set MR parameters:**
   - Target remote: `upstream`
   - Target branch: the resolved base branch
   - MR type: cross-project (`project_id` + `target_project_id`)

**Do not ask for target remote or target branch** — proceed directly with the auto-resolved values.

#### Scenario B: Same Project (no upstream remote) — Ask

Only `origin` remote exists. Ask the user for the target branch:

First, detect possible target branches:
```bash
PARENT_BRANCH=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null | sed 's|^origin/||')
git branch -r | grep -E 'origin/(main|master|develop)' | sed 's|origin/||' | xargs
```

Then ask:
```
請選擇合併目標分支：

1. main
2. develop
3. <detected parent branch> (當前分支的來源)
4. 自訂輸入
```

### 4. Push Branch

Ensure the branch is pushed to origin:

```bash
git push -u origin $(git branch --show-current)
```

### 5. Generate MR Content

#### 5a. Gather Data

```bash
TARGET_BRANCH=<resolved target>
CURRENT_BRANCH=$(git branch --show-current)
MERGE_BASE=$(git merge-base origin/$TARGET_BRANCH $CURRENT_BRANCH 2>/dev/null || git merge-base upstream/$TARGET_BRANCH $CURRENT_BRANCH)

# Commit messages
git log --no-merges --format='%h %s' $MERGE_BASE..$CURRENT_BRANCH

# Full commit bodies (may contain issue references)
git log --no-merges --format='%h %s%n%b' $MERGE_BASE..$CURRENT_BRANCH

# Diff for understanding scope
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

1. **Full URLs** — Match any `https?://...` URLs directly
2. **Issue keys** — Match patterns like `[A-Z]+-\d+` (e.g. `PROJ-123`), `#\d+` (e.g. `#42`)

Deduplicate all extracted references, then:

- Full URLs → use as-is
- Issue keys + `issue_tracker_base_url` provided → build links (e.g. `[PROJ-123](<base_url>/browse/PROJ-123)`)
- Issue keys found but no base URL → use AskUserQuestion to ask for the base URL
- No references found → omit the Related Issues section entirely

#### 5d. Generate Description

Analyze the diff content and commit messages, then generate:

```markdown
## 📋 Summary

<!-- 1-2 sentence overview of the MR purpose -->

## ✨ Changes

<!-- One bullet per logical change. Do NOT prefix bullets with emoji — the section header's emoji is sufficient. Stacking emoji on every line is visual noise and makes the description harder to scan. -->

- 加入使用者登入 API endpoint，支援 email/password 認證
- 新增登入流程的單元測試與整合測試

## 🧪 Test Plan

- [ ] [Testing checklist items based on changes]

## 🔗 Related Issues

<!-- Auto-extracted from commits; omit if none found -->
- [PROJ-123](https://myteam.atlassian.net/browse/PROJ-123)
```

**Section headers are fixed** — always use `## 📋 Summary`, `## ✨ Changes`, `## 🧪 Test Plan`, `## 🔗 Related Issues`. Don't substitute the header emoji per MR type (e.g. don't swap `✨ Changes` for `🐛 Changes` on a bug-fix MR); keeping them stable lets reviewers scan consistent structure across MRs.

### 6. Extract Project Identifiers

```bash
# Extract project path (supports both SSH and HTTPS URLs)
ORIGIN_PROJECT=$(git remote get-url origin | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's|\.git$||')
```

For fork scenario, also extract upstream project path and resolve its numeric ID:

```bash
UPSTREAM_PROJECT=$(git remote get-url upstream | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|' | sed 's|\.git$||')
```

Call `mcp__gitlab__get_project` with URL-encoded upstream project path to get its numeric `id` for `target_project_id`.

**Important:** The project path for GitLab MCP must include the full namespace. If `git remote get-url` returns a deeply nested path (e.g. `moxa/sw/switch/general/linuxframework/one-ui`), use the full path — not just the last two segments.

```bash
# For deeply nested GitLab groups, extract the full path after the host
ORIGIN_PROJECT=$(git remote get-url origin | sed -E 's|.*gitlab\.com[:/](.+?)(\.git)?$|\1|' | sed 's|\.git$||')
UPSTREAM_PROJECT=$(git remote get-url upstream 2>/dev/null | sed -E 's|.*gitlab\.com[:/](.+?)(\.git)?$|\1|' | sed 's|\.git$||')
```

### 7. Create MR via GitLab MCP

#### Scenario A: Same Project

```
project_id: <origin project path, URL-encoded>
source_branch: <current branch>
target_branch: <user selected target branch>
title: <generated title>
description: <generated description>
```

#### Scenario B: Cross Project (Fork)

```
project_id: <origin project path, URL-encoded>
target_project_id: <upstream numeric project ID>
source_branch: <current branch>
target_branch: <auto-resolved target branch>
title: <generated title>
description: <generated description>
```

### 8. Report Results

After MR creation, report:
- MR URL
- MR number
- Source branch → Target branch
- Target remote (origin or upstream)
- Commits included

## Auto-Resolution Summary

| Condition | Branch | Target Remote | Target Branch | Ask User? |
|-----------|--------|--------------|---------------|-----------|
| upstream exists | feature/* off main | upstream | main | No |
| upstream exists | feature/* off nos-v6.0-develop | upstream | nos-v6.0-develop | No |
| upstream exists | target not found on upstream | upstream | — | Yes (fallback) |
| no upstream | any | origin | — | Yes |

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

**Target branch not found on upstream:**
```
自動偵測的目標分支 <branch> 在 upstream 上不存在。
請選擇目標分支：
1. <list of upstream branches>
2. 自訂輸入
```
