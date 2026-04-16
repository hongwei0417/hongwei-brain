---
name: close-ticket
allowed-tools: AskUserQuestion, mcp__mcp-atlassian__jira_get_issue, mcp__mcp-atlassian__jira_get_transitions, mcp__mcp-atlassian__jira_transition_issue, mcp__mcp-atlassian__jira_add_comment, mcp__gitlab__get_merge_request
description: Close a Jira ticket after all MRs are merged — transitions the issue to Done (non-bug) or Resolved (bug) and adds a tracking comment with both MR links (source repo MR + app_moxa_web_scm MR). Use when the user says "close ticket", "關閉票", "結案", "close Jira", "update ticket status", or wants to finalize a Jira ticket after SCM MR is merged.
---

# Close Ticket Skill

## Overview

This skill is the final step in the development workflow. After both MRs (source repo + app_moxa_web_scm) are merged, it transitions the Jira ticket to its terminal status and leaves a tracking comment linking both MRs for future reference.

## Inputs

- **Required:** Jira ticket key (e.g. `PROJ-123`) and two GitLab MR URLs.
- If any input is missing, ask via `AskUserQuestion`:
  1. Jira ticket key — "請提供 Jira ticket（例如 PROJ-123）"
  2. Source repo MR URL — "請提供主 repo 的 MR 連結"
  3. app_moxa_web_scm MR URL — "請提供 app_moxa_web_scm 的 MR 連結"

Accept MR URLs in any GitLab URL format:
```
https://gitlab.com/<group>/<subgroup>/<project>/-/merge_requests/<iid>
```

## Workflow

### Phase 1 — Fetch Ticket and MR Status

Execute these in parallel:

1. **Fetch Jira ticket** via `mcp__mcp-atlassian__jira_get_issue` — capture:
   - issue type (`Bug`, `Task`, `Story`, etc.)
   - current status
   - summary (title)

2. **Fetch both MRs** via `mcp__gitlab__get_merge_request` — for each, capture:
   - state (must be `merged`)
   - title
   - web_url
   - target_branch

#### Validation

- If the Jira ticket is already in a terminal state (Done / Resolved / Closed), stop and report: "Ticket 已經是 <status> 狀態，無需再次更新。"
- If either MR is **not** merged, stop and report which MR is still open: "以下 MR 尚未合併，請等待合併後再執行：\n- <mr_url> (狀態: <state>)"

### Phase 2 — Determine Target Status and Preview ⛳ CHECKPOINT

Determine the target status based on issue type:

| Issue Type | Target Status |
|-----------|--------------|
| `Bug` | **Resolved** |
| All others (`Task`, `Story`, `Sub-task`, etc.) | **Done** |

Fetch available transitions via `mcp__mcp-atlassian__jira_get_transitions` to find the transition ID that leads to the target status. Match by target status name (case-insensitive).

If the target status is not available in the transitions list, report the available transitions and ask the user to pick one.

Present a preview to the user:

```
## Ticket 結案預覽

**Ticket:** <key> — <summary>
- 類型: <issue_type>
- 目前狀態: <current_status>
- 目標狀態: <target_status>

**MR 追蹤連結:**
1. 主 repo MR: <source_mr_url> — <source_mr_title>
2. SCM MR: <scm_mr_url> — <scm_mr_title>

**將執行的動作:**
1. 新增 comment（包含兩個 MR 連結）
2. 切換狀態至 <target_status>

是否確認執行？
```

Use `AskUserQuestion` to confirm:
- **Confirm** → proceed to Phase 3
- **Change target status** → let user pick a different status
- **Abort** → stop

### Phase 3 — Add Comment and Transition

#### Step 1 — Add tracking comment

Use `mcp__mcp-atlassian__jira_add_comment` to add a comment with this format:

```
h3. MR 追蹤

||  || MR || 分支 ||
| 主 repo | [<source_mr_title>|<source_mr_url>] | {{<source_target_branch>}} |
| SCM | [<scm_mr_title>|<scm_mr_url>] | {{<scm_target_branch>}} |
```

Note: Jira uses its own wiki markup, not Markdown. Use `[text|url]` for links, `||` for table headers, `|` for table cells, `{{text}}` for monospace, and `h3.` for headings.

#### Step 2 — Transition the ticket

Use `mcp__mcp-atlassian__jira_transition_issue` with the transition ID found in Phase 2.

If the transition fails (e.g. required fields not set, workflow constraint), report the error and suggest the user do it manually via the Jira UI.

### Final Report

```
## Ticket 結案完成

**Ticket:** <key> — <summary>
- 狀態: <previous_status> → ✅ <new_status>
- Comment: 已新增（含 2 個 MR 追蹤連結）

**MR 連結:**
1. <source_mr_url>
2. <scm_mr_url>
```

## Guardrails

- **Never transition without user confirmation.** The Phase 2 checkpoint is mandatory.
- **Always add the comment before transitioning.** If the comment fails, stop — do not transition without the tracking record.
- **Never fabricate MR URLs or ticket keys.** Only use values provided by the user or fetched from APIs.
- **If any API call fails,** stop and report the exact error. Do not continue with partial state.
- **Never close a ticket whose MRs are not all merged.** Both MRs must be in `merged` state.

## Out of Scope

- Creating or modifying MRs (that's sync-web-scm's job).
- Verifying artifact builds (that's verify-and-sync's job).
- Assigning or re-assigning tickets.
- Modifying ticket fields other than status and comments.
