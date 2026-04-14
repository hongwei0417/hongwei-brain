---
name: do-ticket
allowed-tools: Skill, Grep, Glob, Read, AskUserQuestion, Bash(git status:*), Bash(git branch:*), mcp__mcp-atlassian__jira_get_issue, mcp__mcp-atlassian__jira_search, mcp__mcp-atlassian__jira_get_issue_link_types, mcp__mcp-atlassian__jira_get_link_type, mcp__mcp-atlassian__confluence_get_page, mcp__mcp-atlassian__confluence_search
description: End-to-end Jira-ticket-to-implementation workflow for the switch codebase (apps/switch, libs/switch). Fetches one or more Jira tickets via mcp-atlassian, analyzes requirements, searches the Angular/TypeScript codebase for related functionality, confirms direction with the user, then delegates plan writing and execution to the superpowers skills. Use whenever the user hands over Jira ticket links (newline or space separated) and asks to "do this ticket", "implement this Jira", "handle this ticket", "work on these tickets", or similar phrasing — even if they don't explicitly name superpowers or planning.
---

# Do Ticket Skill

## Overview

This skill turns one or more Jira tickets into a confirmed implementation plan and then executes it in the `switch` codebase. It is an orchestration skill: the heavy lifting of planning and execution is delegated to the `superpowers` family of skills. Your job is to bridge **ticket context** ↔ **codebase reality** ↔ **superpowers**, with the user kept in the loop at three checkpoints.

The three checkpoints exist for a reason:
1. **Direction** — before any plan is written, the user must agree on *what* we are changing and roughly *where*.
2. **Plan** — before any code is written, the user must sign off on the plan that superpowers produces.
3. **Final review** — after execution completes, the user inspects the result as a whole.

If you skip a checkpoint, you will burn tokens generating plans for the wrong interpretation of a ticket, or worse, write code for a misread requirement. Don't skip.

## Inputs

The user will provide one or more Jira ticket links, separated by whitespace or newlines. They may look like:

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

### Phase 2 — Codebase Analysis & Direction Confirmation ⛳

Search **only** under `apps/switch/` and `libs/switch/`. These are Angular/TypeScript; focus on `.ts`, `.html`, `.scss` files.

Good search strategy:
- Start from the "關鍵字/提示" list you extracted in Phase 1 — feature names, component names, route paths, API paths, error strings from the ticket.
- Use `Grep` for literal strings the ticket quoted (error messages, labels, API endpoints) — these are the highest-signal hits.
- Use `Glob` to find files whose names match feature terminology (e.g. `**/device-switch.component.ts`).
- When you find a promising component/service, read enough of it to understand its collaborators, then fan out via imports and template selectors.
- Prefer depth over breadth: it is more useful to fully understand two related components than to list twenty weakly-related files.

Produce a **direction report** and present it to the user. Structure:

```
## 方向分析

### 相關功能 / 模組
- `apps/switch/src/app/.../foo.component.ts:120` — 負責 X，和 PROJ-123 的 Y 需求直接相關
- `libs/switch/data-access/.../bar.service.ts:45` — 提供 Z 的 API 呼叫，Phase 1 digest 中的錯誤訊息來自這裡
- ...

### 影響範圍預估
- 需要修改: <files>
- 可能需要新增: <what kind of file, roughly where>
- 單純參考（不會動）: <files>

### 建議方向
1. <option A — one sentence on approach + trade-off>
2. <option B — alternative if applicable>

### 開放問題 / 需要你確認的點
- ...
```

Then **stop and ask the user**. Use `AskUserQuestion` if the decision space is discrete ("方向 A 還是 B？"), or free-form if you need open feedback. This is an iterative checkpoint — expect to go one or two rounds with the user before the direction is locked in. Do not proceed to Phase 3 until the user clearly confirms ("OK / 確認 / 好 / 就這樣做").

If the user's feedback reveals the ticket scope is wrong (e.g. they want something outside your search area), loop back: re-search with new keywords, update the direction report, re-confirm.

### Phase 3 — Plan via superpowers ⛳

Once direction is confirmed, delegate plan writing to superpowers. Do NOT write the plan yourself — the `superpowers:writing-plans` skill is designed for this and follows a specific structure that `superpowers:executing-plans` expects downstream.

Invoke, in order:

1. **`superpowers:brainstorming`** — pass the confirmed direction, the requirements digest, and the list of relevant files you identified in Phase 2. This skill explores intent/design before implementation and will surface edge cases you missed.
2. **`superpowers:writing-plans`** — after brainstorming is done, invoke this to turn the confirmed approach into a step-by-step implementation plan. Give it the brainstorming output plus your Phase 2 findings so it has concrete file paths to work with.

When the plan is ready, present it to the user for review. Don't paraphrase — show them what `writing-plans` produced. Ask: "Plan 看起來 OK 嗎？需要調整哪裡？"

If the user wants changes, update the plan (either by re-running `writing-plans` with new input or editing the plan file directly for small tweaks) and re-confirm. Do not proceed to Phase 4 until the user confirms.

### Phase 4 — Execute via superpowers

Once the plan is confirmed, invoke **`superpowers:executing-plans`** to carry it out. Let it run end-to-end — do not interrupt it with intermediate reviews unless something is obviously going off the rails (e.g. the executing-plans skill itself asks for clarification, or a checkpoint the user explicitly asked for).

The user has said they only want **one review at the end**, so resist the urge to narrate every step. Short progress updates at phase boundaries are fine; running commentary is noise.

### Phase 5 — Final Review

When execution completes, present a final summary to the user:

```
## 完成報告

### 對應 Ticket
- PROJ-123, PROJ-456

### 實際變更
- <file>: <one-line description of change>
- ...

### 驗證狀態
- 是否有執行 type check / test / build？結果？
- 已知未驗證的部分？

### 待辦 / 後續
- Commit、push、開 MR 等下一步動作（如果還沒做）
```

Then hand control back to the user. Do not auto-commit or push unless the plan explicitly included those steps and the user approved. Normal flow is: user reviews the diff, then invokes `moxa:git-workflow` (or `/git-workflow`) separately to commit and open the MR.

## Interacting with mcp-atlassian

The exact tool names under `mcp__mcp-atlassian__*` may vary by installation. When you first need a Jira tool, if you're unsure which one to use, list the tools the MCP exposes and pick the one whose name and description match "fetch issue by key". Pass issue keys, not URLs.

If the MCP is not installed or authentication fails, stop and tell the user clearly — do not try to guess ticket content from the URL alone.

## Scope Discipline

Things this skill does NOT do:
- Search outside `apps/switch/` and `libs/switch/`. If the user's direction genuinely requires changes elsewhere (e.g. a shared lib in `libs/common/`), raise it during direction confirmation and get explicit approval before expanding scope.
- Commit or push code. That is `moxa:git-workflow`'s job.
- Skip checkpoints to "move faster". The checkpoints are the point of this skill.
- Write the plan itself. Delegate to `superpowers:writing-plans`.

## Why this structure

Jira tickets are notoriously under-specified — a two-sentence ticket often hides three design decisions. By front-loading ticket analysis and codebase grounding before planning, and by gating with a direction checkpoint, we make sure the plan that `superpowers:writing-plans` produces is for the *right* problem. Most wasted implementation cycles come from planning against a misread ticket, not from bad coding — this skill attacks that failure mode.
