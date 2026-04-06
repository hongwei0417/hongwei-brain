---
name: sync-upstream
allowed-tools: Bash(git pull:*), Bash(git fetch:*), Bash(git push:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git merge --abort:*), Bash(git rebase --abort:*), Bash(git remote:*), AskUserQuestion
description: Synchronize the current local branch with its upstream remote tracking branch using git pull. Uses pull with merge for main/master branches and pull with rebase for all others, handles conflicts gracefully by restoring state, and optionally pushes after sync. Use when needing to "sync with upstream", "pull latest changes", "update branch from remote", or "rebase on upstream".
---

# Sync Upstream Skill

## Overview

Synchronize the current local branch with its tracked upstream (remote tracking) branch using `git pull`. Automatically selects merge or rebase strategy based on branch name and handles conflicts safely.

## Workflow

### Phase 1: Detect Branch and Upstream State

Gather current branch information and upstream tracking configuration:

```bash
# Get current branch name
git rev-parse --abbrev-ref HEAD

# Check if current branch has an upstream tracking branch
git rev-parse --abbrev-ref @{upstream} 2>/dev/null
```

**If no upstream is configured:**
- Execute `git fetch --all` to retrieve latest remote references
- Inform the user that the current branch has no upstream tracking branch configured
- Report fetch results and stop — no pull is needed

**If upstream exists**, proceed to Phase 2.

### Phase 2: Check Sync Status

```bash
# Fetch latest from the upstream remote
git fetch

# Check divergence between local and upstream
git log --oneline HEAD..@{upstream}
git log --oneline @{upstream}..HEAD
```

Report the sync status:
- How many commits the local branch is **behind** upstream
- How many commits the local branch is **ahead** of upstream
- If already up-to-date, inform the user and skip to Phase 4 (push prompt)

### Phase 3: Pull with Strategy

Determine the pull strategy based on the current branch name:

#### Main/Master Branch → Pull with Merge

If the current branch is `main` or `master`:

```bash
git pull --no-rebase
```

If the pull produces conflicts:
1. Capture conflicting files: `git diff --name-only --diff-filter=U`
2. Run `git merge --abort` to restore the pre-merge state
3. Report the conflicting files to the user
4. **Stop execution** — do not proceed to push

#### Other Branches → Pull with Rebase

If the current branch is anything other than `main` or `master`:

```bash
git pull --rebase
```

If the pull produces conflicts:
1. Run `git rebase --abort` to restore the pre-rebase state
2. Report the conflicting files to the user
3. **Stop execution** — do not proceed to push

### Phase 4: Post-Sync

After a successful pull:

1. Show a summary of changes synced (commit count, key changes)
2. Ask the user whether to push immediately:
   - If the branch was rebased, push requires `--force-with-lease` — warn the user about this before proceeding
   - If the branch was merged, a normal `git push` is sufficient
3. If the user confirms, execute the push:

```bash
# For merged branches (main/master)
git push

# For rebased branches (force-with-lease for safety)
git push --force-with-lease
```

## Conflict Handling Policy

- **Always abort** on conflicts — never leave the working tree in a conflicted state
- **Always report** the conflicting files before aborting
- **Never attempt** automatic conflict resolution
- After aborting, the working tree is restored to its exact pre-sync state

## Edge Cases

- **Detached HEAD**: If `git rev-parse --abbrev-ref HEAD` returns `HEAD`, inform the user that sync requires being on a named branch and stop
- **Uncommitted changes**: Before starting sync, check `git status --porcelain`. If there are uncommitted changes, warn the user and recommend committing or stashing first before proceeding
- **No remote configured**: If `git remote` returns empty, inform the user that no remote is configured and stop
