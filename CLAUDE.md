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
  - `moxa:create-pr` — Detects fork scenarios, creates GitLab MRs via GitLab MCP (same-project and cross-project)

- **`/sync-from`** — One-way sync from a source branch to target branches:
  - `<source> <target1> [target2...]` — First arg is source, rest are targets
  - No args — Interactive mode asking for source and target branches
  - Flow: one-way comparison (source → each target) → show report → confirm → cherry-pick + create MRs
  - Sync branch naming: `sync/from-<source>-to-<target>`

- **`/sync-branches`** — Multi-directional sync across multiple branches:
  - `<branch1> <branch2> [branch3...]` — Specify branch names (all branches are equal peers)
  - No args — Interactive mode asking for branch names
  - Flow: pairwise comparison of all branches → aggregate missing commits per branch with source annotations → show sync status report → confirm → cherry-pick + create MRs

- **Sync Point Tags**: After each successful cherry-pick sync, a tag `sync-point/from-<source>-to-<target>` is created on the last synced source commit. Scan skills use these tags to narrow future comparisons (only checking commits after the last sync point). Tags are pushed to remote for persistence.

- **Additional Skills:**
  - `moxa:scan-from-branch` — Compares a single source branch against multiple targets one-way to find missing commits per target; uses sync point tags when available to narrow search range
  - `moxa:scan-branches` — Compares all input branches pairwise to find missing commits per branch, deduplicates by commit hash, annotates source branches; uses sync point tags when available
  - `moxa:cherry-pick-sync` — Cherry-picks aggregated commits to a single target branch, creates sync branch, handles conflicts, creates sync point tags on success (called per branch)

Cross-project MR creation uses GitLab MCP with the `target_project_id` parameter (authentication handled by MCP server configuration).

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

## Plugin Versioning

每次修改涉及 plugin 的 commits 時，必須同步更新該 plugin 的 `plugin.json` 中的 `version` 欄位。版號遵循 [Semantic Versioning](https://semver.org/)：

- **MAJOR** (`X.0.0`)：不相容的 API 變更（如移除/重新命名 command、skill 介面變更、破壞性的行為改變）
- **MINOR** (`0.X.0`)：向下相容的功能新增（如新增 command、新增 skill、新增功能特性）
- **PATCH** (`0.0.X`)：向下相容的修正（如 bug fix、文件修正、小幅行為調整、重構）

**判斷依據：** 根據 commit 的 type 決定版號變更幅度：
- `feat` → bump MINOR
- `fix`, `docs`, `refactor`, `chore`, `test`, `style`, `perf` → bump PATCH
- 含 `BREAKING CHANGE` 或 `!` 標記 → bump MAJOR

**注意：** 若同一次提交包含多個 commits，取最高級別的版號變更（MAJOR > MINOR > PATCH）。
