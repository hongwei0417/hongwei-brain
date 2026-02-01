# Moxa Workflow Plugin v1.0

Integrated Git workflow plugin providing create-branch → commit → create-pr flow with fork cross-project MR support.

## Features

- **One-time Setup**: Collect all settings before execution, then run to completion
- **Uninterrupted Execution**: Git operations (create-branch → commit → create-pr) run continuously
- **Flexible Target Branch**: Create PR supports selecting any target branch
- **Fork Support**: Auto-detect fork scenarios, support cross-project MR
- **GitLab Integration**: Via GitLab MCP and direct API operations

## Installation

### Via Marketplace

```bash
/plugin marketplace add hongwei0417/hongwei-brain
/plugin install moxa-workflow@hongwei-brain-marketplace
```

## Usage

### Main Command: `/git-flow`

```bash
# Interactive selection mode
/git-flow

# Full flow mode
/git-flow --full

# Single step mode
/git-flow --step create-branch
/git-flow --step commit
/git-flow --step create-pr
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

Commit changes (built-in `moxa-workflow:commit` skill):

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
/git-flow --full

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
/git-flow --step create-branch

# Only commit
/git-flow --step commit

# Only create PR (specify target branch)
/git-flow --step create-pr
```

## Plugin Structure

```
moxa-workflow/
├── .claude-plugin/plugin.json
├── README.md
├── commands/
│   └── git-flow.md              # Integrated main command
└── skills/
    ├── create-branch/
    │   └── SKILL.md             # Create branch skill
    ├── commit/
    │   └── SKILL.md             # Commit workflow (built-in)
    └── create-pr/
        ├── SKILL.md             # Create PR skill
        └── scripts/
            └── gitlab-cross-project-mr.sh
```

## Dependencies

- Git (required)
- GitLab MCP Server (for same-project MR)
- curl (for cross-project MR API calls)

## License

MIT License
