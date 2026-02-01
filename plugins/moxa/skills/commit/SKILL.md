---
name: moxa:commit
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*)
description: Create well-structured git commits with automatic splitting analysis. Use when committing changes, creating commits, or needing to decide whether to split changes into multiple commits. Triggers on "commit changes", "create commit", "stage and commit", or "commit work".
---

# Commit Skill

## Overview

Create one or more well-structured git commits based on current changes, automatically analyzing whether to split changes into multiple logical commits or combine them into one.

## When to Use

- Committing staged or unstaged changes
- Deciding whether to split changes into multiple commits
- Creating commits with Conventional Commit format
- Ensuring sensitive information is not committed

## Context Gathering

Before committing, gather current state:

```bash
# Check git status
git status

# View staged and unstaged changes
git diff HEAD

# Check current branch
git branch --show-current

# Review recent commits for style reference
git log --oneline -10
```

## Commit Analysis Process

### 1. Analyze Changes

Review all changes and categorize them:

**Change Categories:**
- **Features** (`feat`): New functionality
- **Fixes** (`fix`): Bug fixes
- **Refactoring** (`refactor`): Code restructuring without behavior change
- **Documentation** (`docs`): Documentation updates
- **Style** (`style`): Formatting, whitespace
- **Tests** (`test`): Adding or updating tests
- **Chores** (`chore`): Maintenance tasks, config changes
- **Performance** (`perf`): Performance improvements

### 2. Determine Commit Strategy

**Single Commit When:**
- All changes serve one purpose
- Changes are in closely related files
- Changes represent a single logical unit of work
- Small, focused changes

**Multiple Commits When:**
- Changes span different concerns (feature + fix + docs)
- Unrelated files modified together
- Large change set that can be logically separated
- Different types of changes mixed together

**Decision Criteria:**
1. Can each commit stand alone and make sense?
2. Would separating improve git history readability?
3. Are there distinct logical units?

### 3. Commit Execution

**For Single Commit:**
```bash
# Stage all changes
git add <files>

# Create commit with conventional format
git commit -m "<type>(<scope>): <description>"
```

**For Multiple Commits:**
```bash
# First logical unit
git add <files-for-first-commit>
git commit -m "<type>(<scope>): <description>"

# Second logical unit
git add <files-for-second-commit>
git commit -m "<type>(<scope>): <description>"

# Continue for remaining units...
```

## Conventional Commit Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Restructuring
- `perf`: Performance
- `test`: Tests
- `chore`: Maintenance

**Scope:** Component or area affected (optional but recommended)

**Description:**
- Use imperative mood ("add" not "added")
- No period at end
- Keep under 50 characters

**Examples:**
```
feat(auth): add login validation
fix(api): resolve null pointer in parser
docs(readme): update installation steps
refactor(db): extract connection pooling logic
chore(deps): update dependencies
```

## Security Checks

Before committing, verify no sensitive data:

- API keys or tokens
- Passwords or credentials
- Private keys
- Environment-specific secrets
- Personal information

If detected, warn user and exclude from commit.

## Examples

### Example 1: Single Focused Change

**Changes:** Modified `src/auth/login.ts` with new validation

**Analysis:** Single purpose, one file → Single commit

**Result:**
```bash
git add src/auth/login.ts
git commit -m "feat(auth): add input validation to login form"
```

### Example 2: Multiple Concerns

**Changes:**
- `src/api/user.ts` - Fixed null check bug
- `docs/README.md` - Updated API documentation
- `tests/user.test.ts` - Added new test cases

**Analysis:** Three different concerns → Three commits

**Result:**
```bash
# Commit 1: Bug fix
git add src/api/user.ts
git commit -m "fix(api): add null check in user endpoint"

# Commit 2: Documentation
git add docs/README.md
git commit -m "docs(api): update user endpoint documentation"

# Commit 3: Tests
git add tests/user.test.ts
git commit -m "test(user): add test cases for edge conditions"
```

### Example 3: Related Feature Work

**Changes:**
- `src/components/Theme.tsx` - Added dark mode toggle
- `src/styles/dark.css` - New dark mode styles
- `src/utils/theme.ts` - Theme utility functions

**Analysis:** All serve same feature → Single commit

**Result:**
```bash
git add src/components/Theme.tsx src/styles/dark.css src/utils/theme.ts
git commit -m "feat(ui): implement dark mode toggle with styles"
```

## Process Summary

1. **Gather Context**: Check status, diff, branch, recent commits
2. **Analyze Changes**: Categorize by type and concern
3. **Decide Strategy**: Single or multiple commits
4. **Execute**: Stage and commit in logical order
5. **Verify**: Confirm commits created successfully

## Best Practices

- Each commit should be atomic and focused
- Commit message should explain "why" not just "what"
- Keep commits small enough to review easily
- Ensure each commit passes tests independently
- Use consistent formatting and style
