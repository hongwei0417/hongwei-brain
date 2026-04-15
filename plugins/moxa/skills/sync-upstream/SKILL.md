---
name: sync-upstream
allowed-tools: Bash(git pull:*), Bash(git fetch:*), Bash(git push:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git merge --abort:*), Bash(git rebase --abort:*), Bash(git remote:*)
description: Synchronize the current local branch with the matching branch on the `upstream` remote (from `git remote -v`) using git pull, then push the synced result to the branch's own tracking remote. Uses pull with merge for main/master branches and pull with rebase for all others, handles conflicts gracefully by restoring state. Use when needing to "sync with upstream", "pull latest changes", "update branch from upstream remote", or "rebase on upstream".
---

# Sync Upstream Skill

## Overview

Synchronize the current local branch with the matching branch on the `upstream` remote (as listed in `git remote -v`), then push the synced result to the branch's own tracking remote (typically `origin`). Automatically selects merge or rebase strategy based on branch name and handles conflicts safely.

This is the classic fork workflow: pull from `upstream/<branch>`, push to `origin/<branch>`.

## Workflow

### Phase 1: Detect Branch and Upstream State

Gather current branch information, the `upstream` remote, and the tracking remote:

```bash
# Get current branch name
git rev-parse --abbrev-ref HEAD

# List all remotes to verify `upstream` exists
git remote -v

# Check if the current branch has a tracking remote (for the final push)
git rev-parse --abbrev-ref @{upstream} 2>/dev/null
```

**Required state:**
- A remote named `upstream` must exist in `git remote -v`. If not, inform the user that this skill syncs from an `upstream` remote and stop.
- The current branch should have a tracking remote branch (e.g. `origin/<branch>`) for the post-sync push. If not configured, warn the user — the sync can still run, but Phase 4 will need an explicit push target.

The sync source is always `upstream/<current-branch>` — **not** the branch's tracking remote. The tracking remote is only used as the push target in Phase 4.

**If `upstream/<current-branch>` does not exist on the `upstream` remote** (verified in Phase 2 after fetch), inform the user and stop.

### Phase 2: Check Sync Status

```bash
# Fetch latest from the upstream remote specifically
git fetch upstream

# Verify upstream/<branch> exists
git rev-parse --verify upstream/<current-branch> 2>/dev/null

# Check divergence between local and upstream/<branch>
git log --oneline HEAD..upstream/<current-branch>
git log --oneline upstream/<current-branch>..HEAD
```

Report the sync status:
- How many commits the local branch is **behind** `upstream/<branch>`
- How many commits the local branch is **ahead** of `upstream/<branch>`
- If already up-to-date, inform the user and skip to Phase 4 (push prompt) — the tracking remote may still need a push if it's behind.

### Phase 3: Pull with Strategy

Pull from `upstream/<current-branch>` explicitly (not from the tracking remote). Determine the strategy based on the current branch name.

#### Main/Master Branch → Pull with Merge

If the current branch is `main` or `master`:

```bash
git pull --no-rebase upstream <current-branch>
```

If the pull produces conflicts:
1. Capture conflicting files: `git diff --name-only --diff-filter=U`
2. Run `git merge --abort` to restore the pre-merge state
3. Report the conflicting files to the user
4. **Stop execution** — do not proceed to push

#### Other Branches → Pull with Rebase

If the current branch is anything other than `main` or `master`:

```bash
git pull --rebase upstream <current-branch>
```

If the pull produces conflicts:
1. Run `git rebase --abort` to restore the pre-rebase state
2. Report the conflicting files to the user
3. **Stop execution** — do not proceed to push

### Phase 4: Post-Sync Push to Tracking Remote

After a successful pull from `upstream`, **automatically** push the synced branch to its own tracking remote (e.g. `origin`), so the fork stays in sync with upstream. Do **not** ask the user for confirmation — if Phase 3 completed without errors, proceed directly to push.

1. Show a summary of changes synced (commit count, key changes)
2. Identify the tracking remote from Phase 1 (`@{upstream}` — typically `origin/<branch>`)
3. Execute the push to the **tracking remote** (not to `upstream`) based on the strategy used in Phase 3:

```bash
# For merged branches (main/master) — push to tracking remote
git push

# For rebased branches — force-with-lease for safety
git push --force-with-lease
```

4. Report the push result to the user (success or failure). If the push fails, report the error but do not retry automatically.

**Skip auto-push only if:**
- Phase 3 was skipped because the branch was already up-to-date **and** the local branch is not ahead of the tracking remote (nothing to push)
- The branch has no `@{upstream}` tracking remote configured (see Edge Cases) — in that case, report that no push target exists and stop

**Never push back to the `upstream` remote** — it is read-only in this workflow. The push always targets the branch's own tracking remote.

## Conflict Handling Policy

- **Always abort** on conflicts — never leave the working tree in a conflicted state
- **Always report** the conflicting files before aborting
- **Never attempt** automatic conflict resolution
- After aborting, the working tree is restored to its exact pre-sync state

## Edge Cases

- **Detached HEAD**: If `git rev-parse --abbrev-ref HEAD` returns `HEAD`, inform the user that sync requires being on a named branch and stop
- **Uncommitted changes**: Before starting sync, check `git status --porcelain`. If there are uncommitted changes, warn the user and recommend committing or stashing first before proceeding
- **No `upstream` remote**: If `git remote -v` does not list a remote named `upstream`, inform the user that this skill requires an `upstream` remote and stop
- **`upstream/<branch>` missing**: If the matching branch does not exist on the `upstream` remote after `git fetch upstream`, inform the user and stop
- **No tracking remote for push**: If the current branch has no `@{upstream}` tracking remote, the pull still works but Phase 4 needs the user to specify a push target (or set upstream with `-u`)
