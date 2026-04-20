---
name: analyze-ticket
allowed-tools: Grep, Glob, Read, Write, Edit, AskUserQuestion, Skill, Bash(git status:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(mkdir:*), Bash(date:*), mcp__mcp-atlassian__jira_get_issue, mcp__mcp-atlassian__jira_search, mcp__mcp-atlassian__jira_get_issue_link_types, mcp__mcp-atlassian__jira_get_link_type, mcp__mcp-atlassian__confluence_get_page, mcp__mcp-atlassian__confluence_search
description: Jira-ticket analysis skill for the switch codebase (apps/switch, libs/switch). Fetches one or more Jira tickets via mcp-atlassian, searches the Angular/TypeScript codebase for related functionality, and — as soon as analysis completes — writes a concise Markdown analysis report to `.analyze-ticket/<KEY>.md` at the repo root that includes the key code snippets the work will touch. Then confirms direction with the user and updates the report's confirmed-direction section in place. Stops after the report is finalized and direction is confirmed — does NOT write plans or code. Finally classifies the work (bug / 既有功能擴充 / 全新功能), recommends a best-fit downstream tool (/gsd-quick, superpowers, feature-dev, or openspec) with rationale, and invokes it directly after the user confirms. Use whenever the user hands over Jira ticket links and asks to "analyze this ticket", "understand this Jira", "check what this ticket means", "先分析這張票", or similar phrasing.
---

# Analyze Ticket Skill

## Overview

This skill turns one or more Jira tickets into a **confirmed understanding** of what the work is and roughly where it lives in the `switch` codebase. It is deliberately scoped to the *analysis* phase only — it does not write an implementation plan and it does not touch code.

The flow is: fetch tickets → search the codebase (capturing key code snippets along the way) → **immediately persist a Markdown report** (`.analyze-ticket/<KEY>.md`) with the digest, key files, key code snippets, and proposed directions → confirm direction with the user → update the report's confirmed-direction in place → recommend and invoke a downstream tool.

The report is the lasting artefact of this skill: downstream tools read it instead of re-parsing the ticket, and future sessions can recover the analysis without re-running everything. Writing the report *before* the confirmation question — rather than after — means the file is already a complete snapshot of the analysis at the moment the user looks at it. Any tweak from the user is applied by updating the same file, so chat and disk never drift apart.

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

Hold the digest in working memory for Phase 3 — don't paste a long chat version, it will go straight into the report file.

If something is genuinely ambiguous (e.g. the ticket says "fix the dropdown" but there are five dropdowns), note the ambiguity so you can surface it when you ask for confirmation in Phase 3.

### Phase 2 — Codebase Analysis

Search **only** under `apps/switch/` and `libs/switch/`. These are Angular/TypeScript; focus on `.ts`, `.html`, `.scss` files.

Good search strategy:
- Start from the keyword hints you extracted in Phase 1 — feature names, component names, route paths, API paths, error strings from the ticket.
- Use `Grep` for literal strings the ticket quoted (error messages, labels, API endpoints) — these are the highest-signal hits.
- Use `Glob` to find files whose names match feature terminology (e.g. `**/device-switch.component.ts`).
- When you find a promising component/service, read enough of it to understand its collaborators, then fan out via imports and template selectors.
- Prefer depth over breadth: it is more useful to fully understand two related components than to list twenty weakly-related files.

**While searching, collect concrete code snippets for the report.** For the 2–4 files most central to the work, note:
- The file path and the exact line range (e.g. `foo.component.ts:120-140`) of the code that will be touched or that anchors the change.
- The actual snippet text (≤20 lines each) — read enough of the file to grab it cleanly.
- One sentence on **why** this snippet is the load-bearing part for the ticket.

These become the `## 關鍵程式碼` section of the report in Phase 3. Picking them well matters more than exhaustiveness: a reader should be able to skim the snippets and immediately see where the work lands.

If Phase 2 turns up **no matching code** (全新功能 case), that's also a finding — you'll say so explicitly in the report rather than leaving the section empty.

### Phase 3 — Write Report & Confirm Direction ⛳

This phase has two moves, **in this order**: (a) write the report to disk, then (b) ask the user to confirm the direction. The file is what the user and downstream tools act on; the chat is just the pointer to it.

#### Step 3.1 — Write the report

1. Resolve the repo root with `git rev-parse --show-toplevel`. Report directory is `<repo-root>/.analyze-ticket/`. Create it if missing: `mkdir -p <repo-root>/.analyze-ticket`.
2. Filename is the ticket key(s) joined with `_`, suffixed `.md`. **Sort the keys alphabetically** so `PROJ-123` + `PROJ-456` always produces the same path regardless of the order the user typed them — re-running the analysis on the same tickets must hit the same file.
   - Single ticket: `PROJ-123.md`
   - Multiple: `PROJ-123_PROJ-456.md`
3. If the file already exists, **overwrite it**. Re-running analysis is meant to produce an updated snapshot, not a stack of history.
4. Use the `Write` tool with the template below.

##### Report template

Use this exact structure. If a section genuinely has nothing, keep the heading and write `（無）` underneath — the shape stays predictable across tickets, which is what makes downstream tools able to read it mechanically.

````markdown
# 分析報告 — <TICKET-KEYS>

> 產生時間：<YYYY-MM-DD HH:MM>
> Jira：
> - <URL 1>
> - <URL 2>

## TL;DR

<一段話，≤3 句：要動什麼、為什麼、大致範圍。讀這一段就該知道這張票要做什麼。>

## 需求摘要

### <TICKET-KEY> — <title>
- 目標：<一句話>
- 驗收：<一句話或條列>
- 關鍵字：<code search 用的關鍵詞>

<多張票就重複上面的區塊。單張票可以省略「綜合觀察」；多張票或彼此有依賴/衝突時才寫：>

### 綜合觀察
- <是否為同一個 feature 的多張票？還是獨立需求？有無順序依賴？>

## 關鍵程式碼

<2–4 段，涵蓋這次工作最會動到或最需要理解的程式碼。每段含：檔案路徑 + 行號範圍、一句話「為何關鍵」、實際貼上的 code snippet（≤20 行）。這一段是報告的核心——讀者光看這裡就該知道改動會落在哪。>

### `apps/switch/src/app/.../foo.component.ts:120-140`

**為何關鍵：** <一句話——例如「PROJ-123 要求的 X 行為的進入點在這個 handler」。>

```typescript
// ... 實際 120–140 行的程式碼 ...
```

### `libs/switch/data-access/.../bar.service.ts:45-60`

**為何關鍵：** ...

```typescript
...
```

<若 Phase 2 查無既有對應程式碼（全新功能情境），整段替換成：
「（查無既有對應程式碼；本工作為全新模組，將新增檔案如下節所述。）」>

## 預期修改範圍

### 需要修改
- `<path>` — <一句話理由>

### 可能需要新增
- <檔案類型，大概位置，用途>

### 單純參考（不會動）
- `<path>` — <為何值得看但不會動>

## 方向

<初次寫入時，列出候選方向（1–3 個，通常 2 個就夠）：

1. <option A — 一句話 + trade-off>
2. <option B — alternative if applicable>

使用者確認後（Step 3.4），此節改寫為：

### 已確認方向
<使用者 checkpoint 確認的方向。用一段話寫，不是條列，包含 checkpoint 討論中浮出的 clarification——例如「沿用既有的 DeviceSwitchService，不新增新的 data-access 層」、「只改 MDS-L2，RKS 不在這張票範圍」。這段是下游工具會拿來當 task description 的核心。>>

## 開放問題 / 後續追蹤

<雙方同意延後的議題——不是動手阻礙，但值得記下。沒有就寫「（無）」。>

## 相關檔案索引

<Phase 2 看過但沒進「關鍵程式碼」的檔案，供 traceability。沒有相關檔案就整節略過。>
- `<path>` — <一句話>
````

##### After writing

Tell the user in **one line** and nothing more — don't paste the report back into chat:

```
📄 已產生分析報告：.analyze-ticket/PROJ-123.md
```

Then immediately proceed to Step 3.2.

#### Step 3.2 — Ask the user to confirm

Now ask for confirmation. Keep the chat message short: point at the file, surface only what the user must decide (the proposed directions, any ambiguity flagged in Phase 1, any open question that blocks proceeding).

Use `AskUserQuestion` if the decision space is discrete ("方向 A 還是 B？"), free-form if you need open feedback. Example chat message shape:

```
報告已寫好：.analyze-ticket/PROJ-123.md

重點確認：
- 方向 A：<一行>
- 方向 B：<一行>
- 開放問題：<若有>

請看完檔案後選方向或告訴我要調整什麼。
```

This is the one hard checkpoint in this skill. Expect to go 1–2 rounds before direction is locked.

#### Step 3.3 — Iterate if needed

If the user's feedback changes anything material (different file scope, different approach, re-scoped ticket), **update the report file in place** with the `Edit` or `Write` tool — re-search if needed, rewrite the affected sections, then re-ask. Do not let the chat transcript become the source of truth while the file drifts stale.

#### Step 3.4 — Lock in the confirmed direction

Once the user clearly confirms ("OK / 確認 / 好 / 就這樣做"), update the report so the `## 方向` candidate list is replaced by a `### 已確認方向` block capturing the chosen option plus any clarifications surfaced during the checkpoint. Then proceed to Phase 4.

#### Gitignore note

`.analyze-ticket/` lives in the target repo (e.g. `switch`), not in this plugin. If the user wants the reports gitignored, that's their repo's gitignore to manage — mention it in passing if they ask, but don't modify their `.gitignore` unprompted.

### Phase 4 — Recommend & Hand Off

Once direction is confirmed, **do not** open an undifferentiated menu of tools. Classify the task, recommend one specific tool with a reason, and ask the user to confirm or override. Users push back more productively on a concrete suggestion than on a blank field — and the classification forces you to justify the handoff instead of defaulting to whatever was used last time.

#### Step 4.1 — Classify the task

Combine Phase 1 (ticket metadata) and Phase 2/3 (modification scope) signals. When the two disagree — e.g. the ticket is typed as "Task" but Phase 2 shows a whole new module — use Phase 2/3 as the tiebreaker. What the work actually involves beats what the ticket type claims.

| Bucket | Phase 1 signals | Phase 2/3 signals |
| --- | --- | --- |
| **Bug / 小修改** | issuetype `Bug`; quotes a specific error; short description | 1–2 file edits; no new files; well-localised change |
| **既有功能擴充** | issuetype `Task` / `Improvement`; references an existing feature; has acceptance criteria | 3+ related files; reuses existing components/services; adds behaviour on top of an existing feature |
| **全新功能** | issuetype `Story` / `New Feature`; phrasing like "新功能" / "add ability to"; no obvious existing hook | Needs new module/route/data-access layer; Phase 2 found little or no matching code |

#### Step 4.2 — Map bucket → recommendation

| Bucket | 推薦 | 備選 |
| --- | --- | --- |
| Bug / 小修改 | `/gsd-quick` — atomic commits + state tracking without planning overhead | `superpowers` if you want a plan first for safety |
| 既有功能擴充 | `superpowers` — plan-before-execute with TDD discipline fits multi-file feature work | `feature-dev` (architecture-heavy), `openspec` (spec-first) |
| 全新功能 | `openspec` — change proposal up front keeps the architecture coherent | `superpowers` (design already clear), `feature-dev` |

These are defaults, not laws. If the specific ticket gives you a strong reason to pick a備選 (e.g. a Bug ticket that actually requires a schema change → treat it as 全新功能), follow the reason — and say so in the rationale below.

#### Step 4.3 — Present the recommendation

Before asking, output a short block so the user sees your reasoning:

```
## 工具建議

**分類：** <bucket>
**推薦：<主推工具>**
- 原因：<一句話，引用「關鍵程式碼」找到的檔案或範圍>

**備選：**
- <備選 1>：<何時更適合>
- <備選 2>：<何時更適合>
```

The rationale line must reference *this* ticket's findings — e.g. "三個 component 都走 `device-switch.service`，先寫 plan 再動手成本低" — not the generic table above. If your rationale reads identically across tickets, you're over-relying on issuetype and under-using the 關鍵程式碼 section.

#### Step 4.4 — Confirm via `AskUserQuestion`

Never proceed on the recommendation alone. Offer these options, in this order:

1. **同意推薦（<主推工具>）**
2. **改用 <備選 1>**
3. **改用 <備選 2>**
4. **直接 /gsd-quick 快速實作** — always include this escape hatch, even for "全新功能" buckets; some users prefer speed over ceremony and only they can judge their own time budget
5. **手動 / 先不決定** — user drives next steps, or wants to defer

#### Step 4.5 — Execute the handoff

Route on the user's answer — no extra confirmation round; they already confirmed at 4.4. Pass **the report path** from Phase 3 (e.g. `.analyze-ticket/PROJ-123.md`) as the primary handoff artefact. Telling the downstream tool to read the report file is more reliable than pasting a long block of context into the prompt — the file is the source of truth, the prompt is just a pointer.

- **`/gsd-quick`** — Invoke via the `Skill` tool (`skill: "gsd-quick"`), passing the report path plus the confirmed direction as the task description so the quick executor has the full context.
- **`superpowers`** — Invoke `superpowers:brainstorming` first to pressure-test the confirmed direction against edge cases, then `superpowers:writing-plans`. Execution (`superpowers:executing-plans`) runs later once the plan is ready.
- **`feature-dev`** — Invoke `feature-dev:feature-dev` with the report path.
- **`openspec`** — Help the user scaffold a change proposal under `openspec/` or `libs/switch/_openspec/` (whichever covers the affected area).
- **Manual** — Emit the final handoff pointer (report path + confirmed option) and stop.

**Never** silently default to a previous session's tool. The auto-recommendation is a suggestion; the user's answer at 4.4 is the decision.

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
