# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hongwei Brain is a Claude Code plugin marketplace containing reusable workflow automation plugins. It currently includes the **moxa** plugin for integrated Git workflows.

There are no build, test, or lint commands — this is a pure plugin marketplace with no compiled code or package dependencies. Validation is done via `claude plugin validate .`.

## Architecture

```
hongwei-brain/
├── .claude-plugin/
│   └── marketplace.json    # Plugin registry — lists all available plugins
└── plugins/
    └── moxa/               # Git workflow plugin
        ├── .claude-plugin/
        │   └── plugin.json # Plugin manifest (commands, skills, metadata)
        ├── commands/       # User-facing slash commands (markdown with YAML frontmatter)
        ├── skills/         # Reusable sub-workflows invoked by commands via Skill tool
        └── README.md
```

**Key concepts:**
- **Marketplace** (`marketplace.json`): Registry of plugins with source paths and metadata.
- **Plugins** (`plugin.json`): Each plugin declares its commands, skills, and metadata.
- **Commands**: User-facing entry points (e.g., `/git-workflow`). Defined as markdown files with YAML frontmatter specifying `allowed-tools`, `description`, and `arguments`.
- **Skills**: Reusable components invoked programmatically by commands. Each skill has a `SKILL.md` with YAML frontmatter (`name`, `allowed-tools`, `description`) and markdown workflow instructions.

## Moxa Plugin

The moxa plugin provides a three-phase Git workflow: **create-branch → commit → create-pr**.

- **`/git-workflow`** — Main command with three modes:
  - `--full` — Runs all three phases sequentially after collecting settings upfront
  - `--step <name>` — Runs a single step (`create-branch`, `commit`, or `create-pr`)
  - No args — Interactive mode letting user choose

- **Skills:**
  - `moxa:create-branch` — Creates feature/fix branches with optional worktree support
  - `moxa:commit` — Analyzes changes, decides single vs. multi-commit strategy, uses conventional commits
  - `moxa:create-pr` — Detects fork scenarios, creates GitLab MRs (same-project via MCP, cross-project via API)

- **`/sync-from`** — One-way sync from a source branch to target branches:
  - `<source> <target1> [target2...]` — First arg is source, rest are targets
  - No args — Interactive mode asking for source and target branches
  - Flow: one-way comparison (source → each target) → show report → confirm → cherry-pick + create MRs
  - Sync branch naming: `sync/from-<source>-to-<target>`

- **`/sync-branches`** — Multi-directional sync across multiple branches:
  - `<branch1> <branch2> [branch3...]` — Specify branch names (all branches are equal peers)
  - No args — Interactive mode asking for branch names
  - Flow: pairwise comparison of all branches → aggregate missing commits per branch with source annotations → show sync status report → confirm → cherry-pick + create MRs

- **Additional Skills:**
  - `moxa:scan-from-branch` — Compares a single source branch against multiple targets one-way to find missing commits per target
  - `moxa:scan-branches` — Compares all input branches pairwise to find missing commits per branch, deduplicates by commit hash, annotates source branches
  - `moxa:cherry-pick-sync` — Cherry-picks aggregated commits to a single target branch, creates sync branch, handles conflicts (called per branch)

Cross-project MR creation requires a `GITLAB_PERSONAL_ACCESS_TOKEN` set via environment variable or `~/.claude/settings.json`.

## Adding a New Plugin

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json`
2. Add commands in `commands/` and/or skills in `skills/`
3. Register the plugin in `.claude-plugin/marketplace.json`
4. Validate: `claude plugin validate .`

## Plugin Authoring Conventions

- Command and skill files use YAML frontmatter for metadata and tool restrictions
- `allowed-tools` restricts which Bash commands and tools each command/skill can use (security boundary)
- Branch naming follows conventional prefixes: `feature/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`, `hotfix/`
- Commits follow conventional commit format: `<type>(<scope>): <description>`
