# Moxa Workflow Plugin v1.0

Integrated Git workflow plugin providing create-branch → commit → create-pr flow with fork cross-project MR support.

## Features

- **One-time Setup**: Collect all settings before execution, then run to completion
- **Uninterrupted Execution**: Git operations (create-branch → commit → create-pr) run continuously
- **Flexible Target Branch**: Create PR supports selecting any target branch
- **Fork Support**: Auto-detect fork scenarios, support cross-project MR
- **GitLab Integration**: Via GitLab MCP and direct API operations
- **One-Way Sync**: Cherry-pick commits from a source branch to multiple target branches
- **Multi-Directional Sync**: Pairwise comparison across multiple equal-status branches

## Installation

### Via Marketplace

```bash
/plugin marketplace add hongwei0417/hongwei-brain
/plugin install moxa@hongwei-brain-marketplace
```

## Usage

### Main Command: `/git-workflow`

```bash
# Interactive selection mode
/git-workflow

# Full flow mode
/git-workflow --full

# Single step mode
/git-workflow --step create-branch
/git-workflow --step commit
/git-workflow --step create-pr
```

## Full Flow Mode

Flow sequence: **Create Branch → Commit → Create PR**

### Execution Flow

```
┌─────────────────────────────────────┐
│        Phase 1: Collect Settings    │
│                                     │
│  Select steps to execute:           │
│  ☑ Create Branch                    │
│  ☑ Commit                           │
│  ☑ Create PR → Target: develop      │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│   Phase 2: Execute Sequentially     │
│         (Uninterrupted)             │
│                                     │
│  1. Create Branch ─────────────────→│
│  2. Commit ────────────────────────→│
│  3. Create PR                       │
└─────────────────┬───────────────────┘
                  │
┌─────────────────▼───────────────────┐
│        Phase 3: Report Results      │
└─────────────────────────────────────┘
```

## Step Descriptions

### Create Branch

Create a new branch:

- Auto-generate name based on description or changes
- Support worktree setup

### Commit

Commit changes (built-in `moxa:commit` skill):

- Review and stage changes
- Auto-determine whether to split into multiple commits
- Conventional Commit format
- Ensure no sensitive information

### Create PR

Create GitLab Merge Request:

- Support selecting any target branch
- Auto-detect fork scenarios
- Same-project MR: Uses GitLab MCP
- Cross-project MR: Uses GitLab API

**Target Branch Options:**
```
1. main
2. develop
3. <parent branch of current branch>
4. Custom input
```

## GitLab Token Setup

Cross-project MR requires GitLab Personal Access Token:

### Option 1: Environment Variable

```bash
export GITLAB_PERSONAL_ACCESS_TOKEN=glpat-xxxx
```

### Option 2: Claude Settings

In `~/.claude/settings.json`:

```json
{
  "env": {
    "GITLAB_PERSONAL_ACCESS_TOKEN": "glpat-xxxx"
  }
}
```

## Workflow Examples

### Complete Development Flow

```bash
/git-workflow --full

# Phase 1: Collect settings
# [Multi-select] Steps to execute: Branch, Commit, PR
# [Ask] Branch description: add user profile
# [Ask] MR target branch: develop

# Phase 2: Execute sequentially (uninterrupted)
# → Create Branch: feature/add-user-profile ✓
# → Commit: feat(user): add profile page ✓
# → Create PR: !123 ✓

# Phase 3: Report
# Branch: feature/add-user-profile
# Commit: feat(user): add profile page
# MR: !123 https://gitlab.com/...
```

### Single Task

```bash
# Only create branch
/git-workflow --step create-branch

# Only commit
/git-workflow --step commit

# Only create PR (specify target branch)
/git-workflow --step create-pr
```

## Sync Commands

### One-Way Sync: `/sync-from`

```bash
# From source branch to multiple targets
/sync-from switch-mds-g4000 switch-mds-g4100 switch-eis-series

# From source to single target
/sync-from switch-mds-g4000 switch-mds-g4100

# Interactive mode
/sync-from
```

Flow: source → scan each target → show report → cherry-pick + MR per target

### Multi-Directional Sync: `/sync-branches`

```bash
# All branches compared pairwise
/sync-branches switch-mds-g4000 switch-mds-g4100 switch-eis-series

# Interactive mode
/sync-branches
```

Flow: pairwise comparison → aggregate missing commits → cherry-pick + MR per branch

## Plugin Structure

```
moxa/
├── .claude-plugin/plugin.json
├── README.md
├── commands/
│   ├── git-workflow.md          # Integrated main command
│   ├── sync-branches.md         # Multi-directional sync command
│   └── sync-from.md             # One-way sync command
└── skills/
    ├── create-branch/
    │   └── SKILL.md             # Create branch skill
    ├── commit/
    │   └── SKILL.md             # Commit workflow (built-in)
    ├── create-pr/
    │   └── SKILL.md             # Create PR skill
    ├── scan-branches/
    │   └── SKILL.md             # Multi-directional branch comparison
    ├── scan-from-branch/
    │   └── SKILL.md             # One-way branch comparison
    └── cherry-pick-sync/
        └── SKILL.md             # Cherry-pick sync execution
```

## Dependencies

- Git (required)
- GitLab MCP Server (for same-project MR)
- curl (for cross-project MR API calls)

## License

MIT License
