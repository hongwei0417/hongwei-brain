---
name: analyze-ticket
allowed-tools: Grep, Glob, Read, AskUserQuestion, Bash(git status:*), Bash(git branch:*), mcp__mcp-atlassian__jira_get_issue, mcp__mcp-atlassian__jira_search, mcp__mcp-atlassian__jira_get_issue_link_types, mcp__mcp-atlassian__jira_get_link_type, mcp__mcp-atlassian__confluence_get_page, mcp__mcp-atlassian__confluence_search
description: Jira-ticket analysis skill for the switch codebase (apps/switch, libs/switch). Fetches one or more Jira tickets via mcp-atlassian, produces a requirements digest, searches the Angular/TypeScript codebase for related functionality, and confirms the expected direction and scope of changes with the user. Stops after direction is locked in — does NOT write plans or code. At the end, optionally asks the user which downstream orchestration tool (superpowers / gsd / openspec / manual) should take over for planning and execution. Use whenever the user hands over Jira ticket links and asks to "analyze this ticket", "understand this Jira", "check what this ticket means", "先分析這張票", or similar phrasing.
---

# Analyze Ticket Skill

## Overview

This skill turns one or more Jira tickets into a **confirmed understanding** of what the work is and roughly where it lives in the `switch` codebase. It is deliberately scoped to the *analysis* phase only — it does not write an implementation plan and it does not touch code.

The goal is to bridge **ticket context ↔ codebase reality** with the user kept in the loop at one hard checkpoint: **direction confirmation**. Once the direction is locked in, the skill hands off to a downstream orchestration tool of the user's choice (superpowers, gsd, openspec, or just manual work).

Why split this out: Jira tickets are notoriously under-specified. Most wasted implementation cycles come from planning against a misread ticket, not from bad coding. Front-loading ticket analysis and codebase grounding — without prematurely committing to a planning framework — keeps downstream tools working on the *right* problem and lets the user pick the workflow that fits the task.

## Inputs

The user will provide one or more Jira ticket links, separated by whitespace or newlines:

```
https://<org>.atlassian.net/browse/PROJ-123
https://<org>.atlassian.net/browse/PROJ-456 PROJ-789
```

Bare ticket keys (e.g. `PROJ-123`) without a URL are also acceptable — treat them the same way.

If the user triggers the skill with no tickets supplied, ask for them via `AskUserQuestion` before proceeding.

## Workflow

### Phase 1 — Ingest Tickets

Parse every link/key the user gave you. For each ticket:

1. Use the `mcp-atlassian` Jira tools (e.g. `mcp__mcp-atlassian__jira_get_issue`) to fetch the issue. If the exact tool name differs in this environment, look at the available `mcp__mcp-atlassian__*` tools and pick the one that retrieves an issue by key. Pass the bare key (e.g. `PROJ-123`), not the full URL.
2. Capture: summary, description, status, issue type, priority, labels, components, acceptance criteria (if any), and linked issues.
3. If the ticket references a Confluence page or another Jira ticket that seems load-bearing (e.g. "see PROJ-100 for spec"), fetch that too. Don't go more than one hop deep unless the user asks.

When all tickets are fetched, produce a **requirements digest** for the user. Keep it tight — this is not the place for a 2000-word essay:

```
## 需求摘要

### PROJ-123 — <title>
- 問題 / 目標: ...
- 驗收條件: ...
- 關鍵字/提示: <terms that will help code search>

### PROJ-456 — <title>
...

### 綜合觀察
- 是否為同一個 feature 的多張票？還是獨立的需求？
- 有無互相衝突或順序依賴？
```

Do not ask for confirmation yet — the digest is context for the next phase. If something is genuinely ambiguous (e.g. the ticket says "fix the dropdown" but there are five dropdowns), note the ambiguity so you can resolve it during direction confirmation.

### Phase 2 — Codebase Analysis

Search **only** under `apps/switch/` and `libs/switch/`. These are Angular/TypeScript; focus on `.ts`, `.html`, `.scss` files.

Good search strategy:
- Start from the "關鍵字/提示" list you extracted in Phase 1 — feature names, component names, route paths, API paths, error strings from the ticket.
- Use `Grep` for literal strings the ticket quoted (error messages, labels, API endpoints) — these are the highest-signal hits.
- Use `Glob` to find files whose names match feature terminology (e.g. `**/device-switch.component.ts`).
- When you find a promising component/service, read enough of it to understand its collaborators, then fan out via imports and template selectors.
- Prefer depth over breadth: it is more useful to fully understand two related components than to list twenty weakly-related files.

### Phase 3 — Direction Confirmation ⛳

Produce a **direction report** and present it to the user. This is the one hard checkpoint in this skill — do not skip it, do not rush past it.

```
## 方向分析

### 相關功能 / 模組
- `apps/switch/src/app/.../foo.component.ts:120` — 負責 X，和 PROJ-123 的 Y 需求直接相關
- `libs/switch/data-access/.../bar.service.ts:45` — 提供 Z 的 API 呼叫，Phase 1 digest 中的錯誤訊息來自這裡
- ...

### 預期修改範圍
- 需要修改: <files with one-line rationale each>
- 可能需要新增: <what kind of file, roughly where>
- 單純參考（不會動）: <files>

### 建議方向
1. <option A — one sentence on approach + trade-off>
2. <option B — alternative if applicable>

### 開放問題 / 需要你確認的點
- ...
```

Then **stop and ask the user**. Use `AskUserQuestion` if the decision space is discrete ("方向 A 還是 B？"), or free-form if you need open feedback. This is an iterative checkpoint — expect to go one or two rounds with the user before the direction is locked in. Do not proceed to Phase 4 until the user clearly confirms ("OK / 確認 / 好 / 就這樣做").

If the user's feedback reveals the ticket scope is wrong (e.g. they want something outside your search area), loop back: re-search with new keywords, update the direction report, re-confirm.

### Phase 4 — Handoff

Once direction is confirmed, summarize what is locked in and ask the user how they want to proceed with planning and execution. Do **not** assume a specific orchestration tool — different tasks suit different workflows.

Present the options via `AskUserQuestion`:

- **superpowers** — best for tasks where the user wants a detailed, step-by-step implementation plan generated by `superpowers:writing-plans` followed by `superpowers:executing-plans`. Good for well-scoped, multi-file changes.
- **gsd** — best for tasks that fit into an existing GSD phase structure (`.planning/`). Use when the user is already tracking this work as a GSD phase or wants the `/gsd-plan-phase` → `/gsd-execute-phase` flow.
- **openspec** — best for spec-first changes where an openspec change proposal (`openspec/` or `libs/switch/_openspec/`) should be authored before implementation.
- **manual / 直接開工** — the user will drive planning and execution themselves; your job ends here with the direction report as the handoff document.
- **其他 / 先不決定** — let the user describe what they want.

Pass along to whichever tool is chosen:
1. The requirements digest from Phase 1
2. The direction report from Phase 3 (including the confirmed option and the list of relevant files)
3. Any open questions the user resolved during the checkpoint

If the user picks superpowers, invoke `superpowers:brainstorming` first (to pressure-test the confirmed direction against edge cases), then `superpowers:writing-plans`. If the user picks gsd, route to `/gsd-plan-phase` with the direction report as input. If openspec, help the user scaffold the change proposal. If manual, simply output the final handoff document and stop.

**Never** silently default to superpowers (or any other tool) just because it was the previous default — always ask.

## Interacting with mcp-atlassian

The exact tool names under `mcp__mcp-atlassian__*` may vary by installation. When you first need a Jira tool, if you're unsure which one to use, list the tools the MCP exposes and pick the one whose name and description match "fetch issue by key". Pass issue keys, not URLs.

If the MCP is not installed or authentication fails, stop and tell the user clearly — do not try to guess ticket content from the URL alone.

## Scope Discipline

Things this skill does NOT do:
- Search outside `apps/switch/` and `libs/switch/`. If the user's direction genuinely requires changes elsewhere (e.g. a shared lib in `libs/common/`), raise it during direction confirmation and get explicit approval before expanding scope.
- Write implementation plans. Planning is delegated to whichever orchestration tool the user picks in Phase 4.
- Write or modify code. Execution belongs to downstream tools.
- Commit or push code. That is `moxa:git-workflow`'s job, after execution completes.
- Skip the direction checkpoint to "move faster". The checkpoint is the point of this skill.
- Assume a specific orchestration tool. Always ask the user in Phase 4.
