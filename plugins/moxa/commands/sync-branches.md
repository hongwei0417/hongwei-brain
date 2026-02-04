---
allowed-tools: Bash(git:*), AskUserQuestion, Skill
argument-hint: [--keyword <search>]
description: Cherry-pick sync commits from current branch to other remote branches with automatic MR creation
---

# Sync Branches - Cherry-Pick 同步工作流程

將當前分支的 commits cherry-pick 同步到其他遠端分支，並自動建立 MR。

執行參數: $ARGUMENTS

## 當前倉庫狀態

- 專案目錄: !`basename $(pwd)`
- 當前分支: !`git branch --show-current`
- Git 狀態: !`git status --short`
- Remote 資訊: !`git remote -v`

## 前置檢查

1. **檢查工作目錄是否乾淨：**
   - 如果有未提交的變更，提醒使用者先 commit 或 stash
   - 使用 `git status --short` 確認

2. **檢查當前分支不是 main/master：**
   - 確認當前分支是功能分支而非主分支

## 流程總覽

```
┌──────────────────────────────────────────────────────────────┐
│                    /sync-branches                            │
└───────────────────────┬──────────────────────────────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 1: 搜尋遠端分支    │
           │  輸入關鍵字 → 列出分支   │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 2: 選擇目標分支    │
           │  多選要比對的分支        │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 3: 比對 Commits    │
           │  列出各分支缺少的commits │
           │  自動過濾非功能性commits │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 4: 確認 Commits    │
           │  檢視並調整 commit 清單  │
           │  最終確認                │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 5: 執行同步        │
           │  Cherry-pick + 建立 MR   │
           │  輸出綜合報告            │
           └─────────────────────────┘
```

## 執行步驟

### Step 1: 搜尋遠端分支

觸發 `moxa:scan-branches` skill。

**關鍵字來源：**

**如果 `$ARGUMENTS` 包含 `--keyword`：**
- 使用指定的關鍵字搜尋分支

**否則（預設行為）：**
- 不需詢問關鍵字，自動使用預設搜尋策略：
  1. 掃描 `apps/switch/` 目錄，取得底下所有專案名稱作為關鍵字
  2. 同時搜尋包含 `switch` 關鍵字的分支
- 將兩組結果合併去重後列出

`moxa:scan-branches` 會自動：
- 偵測 remote（upstream 優先，否則 origin）
- 執行 `git fetch` 更新遠端資訊
- 掃描 `apps/switch/` 取得專案名稱，搜尋對應分支
- 搜尋包含 `switch` 關鍵字的分支
- 合併結果後讓使用者多選要比對的目標分支

### Step 2: 比對 Commits

由 `moxa:scan-branches` 繼續處理：
- 比對當前分支與各選定分支的 commits 差異
- 使用 `--cherry-pick` 避免重複已同步的 commits
- 自動過濾非功能性 commits（merge, release, version bump）

### Step 3: 列出差異 Commits 並確認

收到 `moxa:scan-branches` 的結果後，以表格形式展示：

```
## 各分支差異 Commits

### switch-mds-g4000 (5 commits)
  1. ☑ abc1234 feat(api): add new endpoint
  2. ☑ def5678 fix(auth): fix login issue
  3. ☑ ghi9012 refactor: optimize query
  4. ☑ jkl3456 feat(ui): add dashboard
  5. ☑ mno7890 fix(core): memory leak

### switch-mds-g4100 (3 commits)
  1. ☑ abc1234 feat(api): add new endpoint
  2. ☑ def5678 fix(auth): fix login issue
  3. ☑ ghi9012 refactor: optimize query
```

使用 AskUserQuestion 詢問是否有 commits 需要排除：

```
以上是各分支需要同步的 commits。是否有需要排除的 commits？

1. 全部確認，繼續執行
2. 需要排除部分 commits（請說明要排除的 commit hash）
```

如果使用者要排除 commits，從清單中移除後再次確認。

### Step 4: 最終確認

顯示最終執行計畫：

```
## Cherry-Pick Sync 執行計畫

| 目標分支 | Sync 分支名稱 | Commits 數量 |
|----------|--------------|-------------|
| switch-mds-g4000 | sync/<current>-to-switch-mds-g4000 | 5 |
| switch-mds-g4100 | sync/<current>-to-switch-mds-g4100 | 3 |

每個分支會：
1. 建立 sync 分支（基於目標分支）
2. Cherry-pick 所有選定 commits
3. Push 並建立 GitLab MR

遇到衝突時會停止該分支的同步並通知。

確認執行？
```

使用 AskUserQuestion 做最終確認。

### Step 5: 執行 Cherry-Pick 同步

觸發 `moxa:cherry-pick-sync` skill：

- 傳入確認後的分支與 commits 清單
- `moxa:cherry-pick-sync` 會依序：
  1. 基於目標分支建立 `sync/<source>-to-<target>` 分支
  2. Cherry-pick commits（從最舊到最新）
  3. 衝突時中止並清理該分支
  4. 成功後 push 分支
  5. 呼叫 `moxa:create-pr` 建立 MR（固定格式模板）
  6. 切回原始分支
  7. 輸出綜合報告

### 結果報告

最後展示綜合報告，包含：
- 成功同步的分支與 MR 連結
- 失敗（衝突）的分支與衝突資訊
- 統計摘要

## 內部技能

| 步驟 | Skill | 備註 |
|------|-------|------|
| 搜尋與比對分支 | `moxa:scan-branches` | 搜尋分支、比對 commits、過濾非功能 commits |
| 執行 cherry-pick | `moxa:cherry-pick-sync` | Cherry-pick、建立 sync 分支、處理衝突 |
| 建立 MR | `moxa:create-pr` | 建立 GitLab Merge Request |

## 使用範例

```bash
# 預設模式（自動掃描 apps/switch/ 專案名稱 + switch 關鍵字分支）
/sync-branches

# 指定關鍵字搜尋特定分支
/sync-branches --keyword mds

# 搜尋特定專案
/sync-branches --keyword eis-series
```

## 注意事項

1. **工作目錄必須乾淨**：執行前需確保沒有未提交的變更
2. **衝突處理**：遇到衝突會停止該分支的同步，不會強制合併
3. **分支命名**：sync 分支使用 `sync/<source>-to-<target>` 格式
4. **MR 格式**：使用固定模板，列出所有 cherry-pick 的 commits
5. **安全性**：不會修改任何現有分支的 commits，僅建立新的 sync 分支
6. **自動過濾**：自動排除 merge commits、release commits 等非功能性 commits
