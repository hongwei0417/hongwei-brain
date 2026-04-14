---
allowed-tools: AskUserQuestion, Skill
argument-hint: <gitlab-mr-url>
description: Propagate a source GitLab MR into app_moxa_web_scm by pinning the affected product's artifact version in linux_switch_scm_web_config.json and opening follow-up MRs
---

# Sync Web SCM

從一個來源 GitLab MR 產生對應的 `app_moxa_web_scm` 跟進 MR：自動判斷目標 SCM 分支與產品 key、修改 `config/linux_switch_scm_web_config.json`、建立 MR，並附上原始 MR 與 Jira 連結。

執行參數: $ARGUMENTS

## 流程總覽

```
┌──────────────────────────────────────────────────────────────┐
│  /sync-web-scm <gitlab-mr-url>                               │
└───────────────────────┬──────────────────────────────────────┘
                        │
           ┌────────────▼─────────────┐
           │ Phase 1: 解析來源 MR      │
           │  - metadata / diff /     │
           │    commits               │
           │  - Jira links 去重        │
           │  - target 分類            │
           └────────────┬─────────────┘
                        │
           ┌────────────▼─────────────┐
           │ Phase 2: 推斷 SCM 目標    │
           │  - list SCM branches     │
           │  - 讀 example.json schema│
           │  - 提報告 → 使用者確認 ✋ │
           └────────────┬─────────────┘
                        │
           ┌────────────▼─────────────┐
           │ Phase 3: 計算 config 變更 │
           │  - mainline skip 檢查     │
           │  - 詢問 fixed_artifact_ver│
           │  - 產生新 JSON            │
           └────────────┬─────────────┘
                        │
           ┌────────────▼─────────────┐
           │ Phase 4: 預覽 + 建立 MR   │
           │  - 完整 preview → 確認 ✋ │
           │  - 建分支 / commit / MR   │
           │  - 綜合報告               │
           └──────────────────────────┘
```

## 執行步驟

### Step 1: 取得來源 MR URL

- 如果 `$ARGUMENTS` 有提供 URL，直接使用
- 否則使用 `AskUserQuestion` 詢問使用者提供一個 GitLab MR URL

### Step 2: 觸發 `moxa:sync-web-scm` skill

將 URL 傳給 skill，由 skill 執行完整的四個 Phase 流程，包含所有使用者確認檢查點。

## 使用範例

```bash
# 傳入 MR 連結
/sync-web-scm https://gitlab.com/moxa/sw/switch/general/linuxframework/some-repo/-/merge_requests/123

# 互動模式（會詢問 MR URL）
/sync-web-scm
```

## 注意事項

1. **三個使用者確認檢查點**：目標分支解析、artifact 版本確認、最終 preview — 任何一個都不會跳過
2. **不會動本地工作目錄**：所有讀寫透過 GitLab MCP 對遠端進行
3. **Mainline skip 規則**：來源 MR target 是 mainline-like 時，若對應 SCM config 已經是 `default_scm_config` 或 `latest`，自動跳過不建 MR
4. **每個 SCM 分支一個 MR**：同一分支上多個 product keys 會在同一個 MR 裡一起改
5. **Jira 連結**：從 MR description + commit messages 抓並去重
