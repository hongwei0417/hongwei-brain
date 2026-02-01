---
name: moxa-workflow:create-pr
description: Create GitLab Merge Request with automatic fork detection. Handles both same-project MR and cross-project MR (fork to upstream). Supports custom target branch selection. Triggers on "create pr", "create mr", "merge request", "submit pr", or "push and create pr".
---

# Create PR Skill (GitLab)

## Overview

Create GitLab Merge Request with automatic fork detection. Supports both same-project MR (via GitLab MCP) and cross-project MR (fork → upstream via direct API). Allows custom target branch selection.

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
- Use GitLab MCP tools directly

**Scenario B: Fork (origin → upstream)**
- Both `origin` and `upstream` remotes exist
- Need cross-project MR via GitLab API

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

### 6A. Create MR - Same Project (GitLab MCP)

Use `mcp__gitlab__create_merge_request`:

```
project_id: <extracted from origin URL>
source_branch: <current branch>
target_branch: <user selected target branch>
title: <generated title>
description: <generated description>
```

### 6B. Create MR - Cross Project (Direct API)

**Step 1: Get GitLab Token**

```bash
# Try environment variable first
TOKEN=$GITLAB_PERSONAL_ACCESS_TOKEN

# If not set, read from settings
if [ -z "$TOKEN" ]; then
  TOKEN=$(cat ~/.claude/settings.json | jq -r '.env.GITLAB_PERSONAL_ACCESS_TOKEN // empty')
fi
```

**Step 2: Extract Project IDs**

```bash
# Extract project path from URL
ORIGIN_PROJECT=$(git remote get-url origin | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|')
UPSTREAM_PROJECT=$(git remote get-url upstream | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|')

# URL encode
ORIGIN_ENCODED=$(echo "$ORIGIN_PROJECT" | sed 's|/|%2F|g')
UPSTREAM_ENCODED=$(echo "$UPSTREAM_PROJECT" | sed 's|/|%2F|g')
```

**Step 3: Get Source Project ID**

```bash
SOURCE_PROJECT_ID=$(curl -s --header "PRIVATE-TOKEN: $TOKEN" \
  "https://gitlab.com/api/v4/projects/$ORIGIN_ENCODED" | jq -r '.id')
```

**Step 4: Create Cross-Project MR**

```bash
curl -s --request POST \
  --header "PRIVATE-TOKEN: $TOKEN" \
  --header "Content-Type: application/json" \
  --data '{
    "source_branch": "<branch>",
    "target_branch": "<user selected target branch>",
    "title": "<title>",
    "description": "<description>",
    "source_project_id": <SOURCE_PROJECT_ID>
  }' \
  "https://gitlab.com/api/v4/projects/$UPSTREAM_ENCODED/merge_requests"
```

### 7. Report Results

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

## Token Configuration

Users should configure GitLab token in one of these ways:

**Option 1: Environment Variable**
```bash
export GITLAB_PERSONAL_ACCESS_TOKEN=glpat-xxxx
```

**Option 2: Claude Settings**
In `~/.claude/settings.json`:
```json
{
  "env": {
    "GITLAB_PERSONAL_ACCESS_TOKEN": "glpat-xxxx"
  }
}
```

**Required Token Scopes:**
- `api` - Full API access
- `read_repository` - Read repository
- `write_repository` - Write repository

## Error Handling

**No token found:**
```
錯誤：找不到 GitLab Token

請設定 GITLAB_PERSONAL_ACCESS_TOKEN：
1. 環境變數: export GITLAB_PERSONAL_ACCESS_TOKEN=glpat-xxxx
2. 或在 ~/.claude/settings.json 中設定
```

**API error:**
- Parse error message from response
- Suggest common fixes (permissions, branch exists, etc.)

## Examples

**Same Project MR to main:**
```
Branch: feature/add-auth
Target: main
Method: GitLab MCP
Result: !123 https://gitlab.com/user/repo/-/merge_requests/123
```

**Same Project MR to develop:**
```
Branch: feature/add-auth
Target: develop (user selected)
Method: GitLab MCP
Result: !124 https://gitlab.com/user/repo/-/merge_requests/124
```

**Cross-Project MR (Fork) to custom branch:**
```
Source: user/repo-fork (feature/add-auth)
Target: original/repo (release/v2.0)
Method: Direct API
Result: !456 https://gitlab.com/original/repo/-/merge_requests/456
```

## Integration Note

When called from `/git-flow`:
- Receives target remote and target branch settings from first phase
- Branch should already be created and pushed
- Reports MR URL as final workflow output
