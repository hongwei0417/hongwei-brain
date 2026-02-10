---
name: create-branch
allowed-tools: Bash(git:*), AskUserQuestion
description: Create a new git branch with optional worktree setup. Use when needing to start new feature development, create fix branches, or set up parallel working directories. Triggers on "create branch", "new branch", "worktree", or "start feature".
---

# Create Branch Skill

## Overview

Create a new git branch based on description with optional worktree setup for parallel development.

## When to Use

- Starting new feature development
- Creating fix/hotfix branches
- Setting up worktree for parallel work
- Organizing branch structure

## Process

### 1. Gather Branch Information

**If description provided:**
- Use provided description to generate branch name

**If no description:**
- Analyze uncommitted changes using `git diff` and `git status`
- Generate description from changes
- Confirm with user

### 2. Generate Branch Name

Follow naming conventions:
- `feature/<name>` - New features
- `fix/<name>` - Bug fixes
- `refactor/<name>` - Refactoring
- `docs/<name>` - Documentation
- `test/<name>` - Testing
- `chore/<name>` - Maintenance
- `hotfix/<name>` - Urgent fixes

**Guidelines:**
- Lowercase with hyphens
- Concise but descriptive (2-5 words)
- Present tense verbs

### 3. Validate Branch

Before creation:
- Check if branch already exists
- Verify naming conventions
- Check for special characters
- Suggest alternatives if conflicts

### 4. Ask Worktree Preference

Use AskUserQuestion to ask:

```
選擇建立方式：

1. Branch Only (建議用於短期工作)
   - 在當前目錄建立並切換到新分支

2. Branch + Worktree (建議用於長期功能開發)
   - 建立獨立工作目錄
   - 可同時在多個分支工作
```

### 5. Execute Creation

**Branch Only:**
```bash
git checkout -b <branch-name>
```

**Branch + Worktree:**
```bash
PROJECT_NAME=$(basename $(pwd))
git worktree add ../${PROJECT_NAME}.worktrees.${BRANCH_NAME} -b ${BRANCH_NAME}
```

**Worktree Directory Structure:**
```
parent-dir/
├── my-project/                          # Main repository
└── my-project.worktrees.feature/
    ├── add-auth/                        # feature/add-auth
    └── dark-mode/                       # feature/dark-mode
└── my-project.worktrees.fix/
    └── memory-leak/                     # fix/memory-leak
```

### 6. Report Results

After creation, report:
- Created branch name
- Current location (worktree path if applicable)
- Next steps suggestion

## Examples

**Input:** "add user authentication"
**Branch:** `feature/add-user-auth`

**Input:** "fix login bug"
**Branch:** `fix/login-bug`

**Input:** (empty, detected changes in auth files)
**Branch:** `feature/auth-improvements`

## Safety Checks

- Verify working directory is clean (or offer to stash)
- Ensure git repository is initialized
- Check disk space for worktree
- Confirm base branch is up to date

## Worktree Management Commands

```bash
# List worktrees
git worktree list

# Remove worktree
git worktree remove ../<project>.worktrees.<branch>

# Prune deleted worktrees
git worktree prune
```
