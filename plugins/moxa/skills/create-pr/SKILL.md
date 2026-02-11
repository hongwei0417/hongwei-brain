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

**Title:**
- From branch name or commit messages
- Keep under 70 characters

**Description Template:**
```markdown
## Summary
- [1-3 bullet points describing changes]

## Test Plan
- [ ] [Testing checklist items]

## Related Issues
- Closes #XXX (if applicable)
```

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
