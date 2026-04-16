---
name: verify-and-sync
allowed-tools: AskUserQuestion, Skill, Read, WebFetch, Bash(git log:*), Bash(git remote:*), mcp__gitlab__get_merge_request, mcp__gitlab__get_project, mcp__claude-in-chrome__*, mcp__chrome-devtools__*
description: Verify a GitLab MR is merged and confirm the corresponding SCM artifact build exists before triggering sync-web-scm. Use when the user says "verify and sync", "check MR and sync SCM", "確認 MR 合併後同步 SCM", "verify build and sync", or hands over a merged MR link and wants to propagate to app_moxa_web_scm. This skill bridges the gap between MR merge and SCM config propagation — it ensures the artifact build is available before creating follow-up MRs.
---

# Verify and Sync Skill

## Overview

This skill is a pre-flight check before SCM config propagation. After a GitLab MR is merged in the source repo, the corresponding artifact must appear on the SCM platform before the `sync-web-scm` skill can meaningfully pin it. This skill automates that verification sequence: **confirm MR merged → find artifact build on SCM → hand off to sync-web-scm**.

## Inputs

- **Required:** one GitLab MR URL.
- If the user triggered the skill with no URL, ask for it via `AskUserQuestion`.

Parse the URL into `(project_path, mr_iid)`. GitLab URLs look like:
```
https://gitlab.com/<group>/<subgroup>/<project>/-/merge_requests/<iid>
```

## Workflow

### Phase 1 — Verify MR is Merged

Fetch the MR via `mcp__gitlab__get_merge_request` using the parsed `(project_path, mr_iid)`.

Check `state`:
- **`merged`** → proceed to Phase 2.
- **`opened`** → stop. Report to user: "MR 尚未合併，請等待 review 完成後再執行此 skill。"
- **`closed`** (not merged) → stop. Report: "MR 已被關閉但未合併，請確認是否為正確的 MR。"

Extract and retain for later phases:
- MR title, description, web_url
- target_branch, source_branch
- merged_at timestamp
- Jira issue keys (scan description + title for `[A-Z][A-Z0-9]+-\d+` patterns)

Report to the user:

```
## MR 狀態確認

**MR:** !<iid> <title>
- 狀態: ✅ 已合併
- 合併時間: <merged_at>
- 目標分支: <target_branch>
- Jira: <keys or "未偵測到">
```

### Phase 2 — Locate Artifact Build on SCM ⛳ CHECKPOINT

Determine which SCM project URL to check based on the source MR's project path:

| Source project path contains | SCM artifact URL |
|------------------------------|-----------------|
| `one-ui` or `one/one-ui` | `https://scm.moxa.com/#moxa/sw/f2e/one/one-ui/` |
| `f2e-networking` or `networking/f2e-networking` | `https://scm.moxa.com/#moxa/sw/f2e/networking/f2e-networking/` |

If the project doesn't match either pattern, ask the user via `AskUserQuestion` which SCM project to check, presenting the two known options plus a custom URL option.

#### Checking the SCM platform

The SCM platform at `scm.moxa.com` is a web application. To verify the artifact build exists:

1. **Use browser automation** to navigate to the appropriate SCM URL. Use `mcp__claude-in-chrome__*` or `mcp__chrome-devtools__*` tools to:
   - Navigate to the SCM project page
   - Look for a build entry that corresponds to the merged MR's target branch and approximate merge time
   - Capture the artifact version identifier (typically a date-stamped path like `v6.0/2026-03-26` or a build number)

2. **If browser tools are unavailable**, ask the user via `AskUserQuestion`:
   ```
   請到 SCM 平台確認 artifact build：
   <scm_url>

   請問是否已找到對應的 build？如果有，請提供 artifact version（例如 v6.0/2026-03-26）。
   ```

3. **If the build is not yet available**, inform the user and suggest waiting:
   ```
   SCM 上尚未找到對應的 artifact build。
   建議稍後再執行此 skill，或手動確認 CI pipeline 狀態。
   ```
   Stop here — do not proceed to Phase 3 without a confirmed build.

Once the artifact build is confirmed (either by browser or user input), present the verification result:

```
## Artifact Build 確認

**SCM 專案:** <scm_url>
**Artifact version:** <version>
- 對應分支: <target_branch>
- 建置時間: <build timestamp if available>

準備進行 sync-web-scm，是否繼續？
```

Use `AskUserQuestion` to confirm before proceeding. The user may want to:
- **Continue** → proceed to Phase 3
- **Use different artifact version** → update the version and re-confirm
- **Abort** → stop

### Phase 3 — Hand Off to sync-web-scm

Invoke the `moxa:sync-web-scm` skill via the `Skill` tool, passing the original MR URL as context.

The sync-web-scm skill will handle:
- Resolving SCM target branches and product keys
- Planning the config change with the artifact version
- Creating follow-up MRs on `app_moxa_web_scm`

**Important:** Pass along the artifact version confirmed in Phase 2 — when sync-web-scm asks for `fixed_artifact_ver` during its Phase 3, use the version already confirmed by the user rather than asking again.

After sync-web-scm completes, collect its output (the created MR URLs) and present a combined summary:

```
## Verify and Sync — 完成報告

### 來源 MR
- **MR:** <web_url>
- **狀態:** ✅ 已合併（<merged_at>）
- **Jira:** <keys>

### Artifact Build
- **SCM:** <scm_url>
- **Version:** <artifact_version>

### SCM Config MR(s)
| SCM 分支 | MR | 產品 | 狀態 |
|----------|-----|------|------|
| <branch> | <mr_url> | <product_keys> | 已建立 |

💡 下一步：等待 SCM MR 合併後，可使用 `close-ticket` skill 來更新 Jira 狀態。
```

## Guardrails

- **Never proceed to sync-web-scm without confirming both MR merged AND artifact build exists.** A premature sync pins a nonexistent build.
- **Never skip the Phase 2 checkpoint.** The user must confirm the artifact version.
- **Never fabricate artifact versions.** Only use versions confirmed from the SCM platform or provided by the user.
- **If any GitLab MCP call fails,** stop and report the error clearly. Do not fall through to partial state.
- **If browser automation fails,** gracefully fall back to asking the user to check manually.

## Out of Scope

- Merging or approving any MR.
- Modifying source code or config files directly (that's sync-web-scm's job).
- Triggering CI/CD pipelines or waiting for builds to complete.
- Updating Jira ticket status (that's close-ticket's job).
