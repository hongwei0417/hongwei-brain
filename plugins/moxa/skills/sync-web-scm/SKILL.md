---
name: sync-web-scm
allowed-tools: AskUserQuestion, Read, Bash(git ls-remote:*), mcp__gitlab__get_merge_request, mcp__gitlab__get_merge_request_diffs, mcp__gitlab__list_merge_request_diffs, mcp__gitlab__list_commits, mcp__gitlab__get_file_contents, mcp__gitlab__create_branch, mcp__gitlab__create_or_update_file, mcp__gitlab__create_merge_request, mcp__gitlab__get_project
description: Propagate a source GitLab MR into the app_moxa_web_scm repo by pinning the affected product's artifact version inside linux_switch_scm_web_config.json on the matching SCM branch(es), then opening follow-up MRs. Use whenever the user hands over a GitLab MR link and asks to "sync to web scm", "sync web scm config", "propagate this MR to app_moxa_web_scm", "pin scm config from MR", "update web scm config", or similar — even if they don't explicitly mention the config file name.
---

# Sync Web SCM Skill

## Overview

This skill takes a single source GitLab MR and produces follow-up MRs against `app_moxa_web_scm` that pin the affected product's artifact version in `config/linux_switch_scm_web_config.json`, so that the SCM web build picks up the source change. Think of it as: **"component change merged → tell the SCM web which artifact version to fetch"**.

The skill is an orchestrator. It never touches the local working tree — every read and write happens through GitLab MCP tools against the remote repos directly.

### The repo you are targeting

`git@gitlab.com:moxa/sw/switch/general/linuxframework/app_moxa_web_scm.git`
- Project path (for GitLab MCP): `moxa/sw/switch/general/linuxframework/app_moxa_web_scm`
- Config schema reference: `config/example.json` (read-only — use to understand the override shape)
- Config to edit: `config/linux_switch_scm_web_config.json`

### Three user checkpoints

You will stop and confirm with the user three times. Do not skip any of them — getting the product key or the SCM branch wrong silently pins the wrong build, and the user has no cheap way to discover the mistake later.

1. **Target resolution** — after you've proposed which SCM branch(es) and which product key(s) to modify.
2. **Artifact version** — when you need the pinned `fixed_artifact_ver` (release branches only).
3. **Final preview** — a full diff + MR body preview before any MR is created.

## Inputs

- **Required:** one GitLab MR URL (source MR).
- If the user triggered the skill with no URL, ask for it via `AskUserQuestion` before proceeding.

Parse the URL into `(project_path, mr_iid)`. GitLab URLs look like:
```
https://gitlab.com/<group>/<subgroup>/<project>/-/merge_requests/<iid>
```

## Workflow

### Phase 1 — Ingest the source MR

Fetch everything you need in as few round-trips as possible. Call these in parallel:

- `mcp__gitlab__get_merge_request` → title, description, target branch, source branch, author, state, web_url
- `mcp__gitlab__list_commits` on the MR (or the equivalent MR-scoped commits tool) → commit list with messages
- `mcp__gitlab__list_merge_request_diffs` / `get_merge_request_diffs` → changed files and diff hunks

From this data extract:

1. **Target branch classification.** Look at `target_branch`:
   - Matches `release/<product-slug>/<version>` (e.g. `release/rks-g4000-l3/v6.0`) → `release-style`. Remember the `<product-slug>` and `<version>`.
   - Anything else that smells like a mainline/develop branch (`main`, `master`, `develop`, `nos-v*/develop`, `nos-v*/main`, etc.) → `mainline-style`.
   - If it's ambiguous, note it and ask the user in Phase 2.

2. **Jira issue links.** Scan the MR description AND every commit message for patterns like:
   - `https://<anything>.atlassian.net/browse/KEY-123`
   - Bare issue keys in the form `[A-Z][A-Z0-9]+-\d+` that look like Jira (not commit SHAs, not version strings)

   Deduplicate by key. Keep the canonical URL form if present; otherwise keep the bare key (you'll render it plainly in the MR body).

3. **Purpose summary.** Read the MR description and the top few commit messages, then write a 1–3 sentence summary of *what* the MR changes and *why*. This goes into the follow-up MR body and into your Phase 2 report — keep it factual and short.

4. **Changed paths (for mainline-style only).** Collect the list of file paths touched. You'll use these to infer candidate products in Phase 2.

Do not present any of this to the user yet — Phase 2 presents a single consolidated report.

### Phase 2 — Resolve SCM target branch(es) and product key(s) ⛳ CHECKPOINT 1

This is the hardest phase. Your job: map the source MR onto `(scm_branch, product_keys_to_edit)` pairs, and get the user to confirm.

First, in parallel, pull the two things you need for planning:

- **List SCM branches.** The GitLab MCP may not expose a branch-list tool directly; if not, use:
  ```
  git ls-remote --heads git@gitlab.com:moxa/sw/switch/general/linuxframework/app_moxa_web_scm.git
  ```
  Parse out the branch names. Cache the list in your working memory.

- **Fetch `config/example.json`** from `develop` via `mcp__gitlab__get_file_contents`, project path `moxa/sw/switch/general/linuxframework/app_moxa_web_scm`, ref `develop`. This tells you the exact shape of the override object (keys like `name`, `rev`, `fixed_artifact_ver`, and what `default_scm_config` looks like). **Do not assume the shape — read it.**

Then resolve targets based on the classification from Phase 1:

#### Case A — `release-style` source MR

The product is already named in the source target branch (`release/<product-slug>/<version>`). Mapping:

1. **Find the SCM branch.** Look in the branch list for a branch that matches the same product and version. Common shapes you may encounter (check against the actual list — don't hard-code):
   - `release/<product-slug>/<version>`
   - `release/<product-slug>-<version>`
   - Sometimes a shared `release/<version>` branch if the repo uses per-version rather than per-product release branches.

   If multiple plausible matches, list them for the user. If none match, fall back to offering the user every `release/*` branch as a pick list.

2. **Derive the product key** from the product slug. Convention appears to be: slug `rks-g4000-l3` → key `RKS-G4000-L3` (uppercase, hyphens preserved). Verify against `example.json` — the keys there show the canonical casing. If the derived key isn't present in `example.json`, surface that as "new product key — please confirm exact casing".

3. **Expect one product key per release-style source MR.** If the user insists on adding more, let them.

#### Case B — `mainline-style` source MR

No product is named in the target branch — you must infer from the diff. Strategy:

1. **Find the SCM branch(es).** Typically this case maps to a develop-like branch in the SCM repo (e.g. `develop`, or `nos-v<X>/develop` matching the source target's `nos-v<X>/` prefix if present). Propose the most plausible one — usually `develop` — but show the user the branch list so they can correct you.

2. **Infer candidate product keys from the diff.** Look at the file paths and diff contents for product-name tokens. Cross-reference every product key present in `config/linux_switch_scm_web_config.json` on the chosen SCM branch (fetch it in this phase — you'll need it in Phase 3 anyway). Any key whose name-slug appears in a changed path is a strong candidate.

3. **If you can't confidently pick, ask.** Present the candidate keys and let the user tick the ones that apply. Remember: multiple products on a single SCM branch is normal for mainline-style changes.

#### Present the Target Resolution Report

Regardless of case, produce a report like:

```
## Target Resolution

**Source MR:** !<iid> <title>
  - target_branch: release/rks-g4000-l3/v6.0   (release-style)
  - purpose: <1-line summary>

**Proposed SCM targets:**

1. SCM branch: release/rks-g4000-l3/v6.0
   - product keys: RKS-G4000-L3
   - reason: matched by product slug + version from source target branch

(…or multiple entries for mainline-style…)

**Jira links detected:** ABC-123, DEF-456
```

Then use `AskUserQuestion` to confirm. Offer three branches:
- Accept as-is
- Edit (change branch / add/remove product keys)
- Abort

Keep iterating on the resolution until the user explicitly confirms. **Do not proceed until the user says yes.**

### Phase 3 — Plan the config change

For each confirmed `(scm_branch, product_keys[])` pair:

1. **Fetch the current config** from that branch:
   `mcp__gitlab__get_file_contents` for `config/linux_switch_scm_web_config.json` on the SCM branch. Parse the JSON. (If you already fetched it during Case B, reuse it.)

2. **Check the mainline-skip rule.** This rule exists because mainline SCM builds already pull `latest`, so an unpinned product automatically gets the new artifact with no human action.

   The rule: **if the source MR is `mainline-style` AND, for a given product key, the current SCM config uses `default_scm_config` OR its `fixed_artifact_ver` contains `latest`, then skip that product key.** Record the skip with a reason — you'll include it in the preview so the user knows why you didn't change it.

   Release-style source MRs never skip — the whole point is to pin a specific version.

3. **Ask for `fixed_artifact_ver` — release-style only.** For each non-skipped product key that needs pinning, use `AskUserQuestion` to ask for the artifact version. Default: `v<X>.<Y>/latest` where `<X>.<Y>` comes from the source MR's release branch version.

   You may batch this question: if there are three product keys on the same SCM branch, ask once per key but present them together.

   For mainline-style changes that aren't skipped (e.g. user explicitly wants to pin even on develop), still ask, same default.

4. **Compute the new JSON.** Build the override block following the shape you learned from `example.json`. For example:
   ```json
   "RKS-G4000-L3": {
     "name": "rks-g4000-l3",
     "rev": "release",
     "fixed_artifact_ver": "v6.0/2026-03-26"
   }
   ```
   - `name`: lowercase product slug
   - `rev`: `release` for release-style, otherwise whatever the example.json uses for develop-like entries
   - `fixed_artifact_ver`: the value from step 3

   Merge this into the existing config. If the key already exists, update the fields that changed; preserve unrelated fields. Preserve JSON formatting as faithfully as you can — match indentation (usually 2 spaces) and key ordering of neighboring entries to minimize noise in the diff.

5. **If an SCM branch ends up with zero applicable changes** (all product keys skipped), mark the whole branch as "no MR needed" and move on. Do not create an empty MR.

### Phase 4 — Final preview and MR creation ⛳ CHECKPOINT 3

Before touching anything, show a complete preview:

```
## Sync Web SCM — Preview

Source MR: <url>
Purpose: <summary>
Jira links: ABC-123, DEF-456

### MR 1
- SCM branch: release/rks-g4000-l3/v6.0
- New branch: chore/scm-pin-rks-g4000-l3-v6.0-2026-03-26
- File: config/linux_switch_scm_web_config.json
- Config diff:
  ```diff
  - "RKS-G4000-L3": { "name": "rks-g4000-l3", "rev": "release", "fixed_artifact_ver": "v6.0/latest" },
  + "RKS-G4000-L3": { "name": "rks-g4000-l3", "rev": "release", "fixed_artifact_ver": "v6.0/2026-03-26" },
  ```
- MR title: chore(scm): pin RKS-G4000-L3 to v6.0/2026-03-26
- MR body preview:
  <full body>

### Skipped
- product-key X on branch develop — already using default_scm_config (mainline skip rule)
```

Ask the user to confirm via `AskUserQuestion` one last time:
- Confirm — create all MRs
- Edit — go back to Phase 3 and redo a specific entry
- Abort

On confirm, for each MR in order:

1. **Create the new branch** off the SCM branch via `mcp__gitlab__create_branch` (project path `moxa/sw/switch/general/linuxframework/app_moxa_web_scm`, branch name `chore/scm-pin-<product-slug>-<artifact-ver-sanitized>`, ref = the SCM branch). Sanitize the artifact version for branch naming: `/` → `-`, spaces → `-`.

   If multiple product keys are being pinned on the same SCM branch, use one branch and commit once — you do not need a branch per key.

2. **Commit the new config** via `mcp__gitlab__create_or_update_file`. Commit message format:
   ```
   chore(scm): pin <product-keys-csv> on <scm-branch>

   Source MR: <url>
   Jira: <keys-csv>
   ```

3. **Create the MR** via `mcp__gitlab__create_merge_request`. Target branch = the SCM branch (NOT `develop` — unless that is the SCM branch). Title = the commit subject. Body format below.

4. **Collect the new MR URL** for the final report.

#### Follow-up MR body template

```markdown
## Purpose

<1–3 sentence summary you wrote in Phase 1>

## Source MR

<original MR url> — <original title>

**Source target branch:** `<original target branch>`

## Config change

Pinning <product-keys-csv> on `<scm-branch>` so SCM web picks up the change from the source MR above.

- `fixed_artifact_ver`: `<value>`

## Jira

- <KEY-1>
- <KEY-2>
```

If no Jira links were found, omit the Jira section (do not write "none"). If more than one product key is pinned in the same MR, list each one's config block under "Config change".

### Final report

After all MRs are created, print a summary table:

```
## Sync Web SCM — Result

Source MR: !<iid> <title>

| SCM branch | MR | Product keys | Status |
|------------|-----|--------------|--------|
| release/rks-g4000-l3/v6.0 | !789 | RKS-G4000-L3 | created |
| develop | (skipped) | X, Y | mainline skip rule |

Jira: ABC-123, DEF-456
```

## Branch naming convention

- New branch in SCM repo: `chore/scm-pin-<product-slug>-<artifact-ver-sanitized>`
  - Single product: `chore/scm-pin-rks-g4000-l3-v6.0-2026-03-26`
  - Multiple products on one SCM branch: use the SCM branch's product train if any, else `chore/scm-pin-multi-<scm-branch-slug>-<date>`

## Guardrails

- **Never write to the local working tree.** All reads and writes go through GitLab MCP.
- **Never bypass the three checkpoints.** If the user is in a hurry, still ask — it takes seconds and prevents wrong pins.
- **Never create an empty or same-content MR.** If the computed config equals the current config byte-for-byte, skip and report why.
- **Never infer a product key from a non-authoritative source.** The authoritative source is: source MR target branch (release case) or the `example.json` + current config keys (mainline case).
- **Never fabricate Jira keys.** Only include keys you actually saw in the description or a commit message.
- **If a GitLab MCP call fails,** stop and report the exact error. Do not retry silently or fall through to a partial state. A half-created MR is worse than a clean abort.

## Out of scope

- Editing any file other than `config/linux_switch_scm_web_config.json`.
- Modifying the source MR.
- Merging, approving, or closing MRs.
- Updating product keys on branches the user did not confirm.
- Any git operation in the local working tree.
