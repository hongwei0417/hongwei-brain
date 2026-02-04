---
allowed-tools: Bash(git:*), AskUserQuestion, Skill
argument-hint: <source-branch> <target1> [target2...]
description: One-way sync — cherry-pick commits from a source branch to one or more target branches with automatic MR creation
---

# Sync From - 單向 Cherry-Pick 同步工作流程

從一個來源分支單向同步 commits 到多個目標分支。找出來源分支有但目標分支沒有的 commits，逐一 cherry-pick 並建立 MR。

**單向同步：只從來源分支流向目標分支，不反向比對。**

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

## 流程總覽

```
┌───────────────────────────────────────────────────────────────┐
│  /sync-from <source> <target1> [target2...]                   │
└───────────────────────┬───────────────────────────────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 1: 單向比對       │
           │  source → target1       │
           │  source → target2       │
           │  source → target3       │
           │  → 找出每個目標缺少的   │
           │    commits              │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 2: 展示同步報告   │
           │  target1 缺: X,Y       │
           │  target2 缺: Z         │
           │  target3: 已同步       │
           │  → 使用者選擇/調整      │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 3: 逐一同步       │
           │  Cherry-pick + 建立 MR  │
           │  輸出綜合報告           │
           └─────────────────────────┘
```

## 執行步驟

### Step 1: 單向比對各目標分支 Commits 差異

觸發 `moxa:scan-from-branch` skill。

**分支名稱來源：**

**如果 `$ARGUMENTS` 有提供分支名稱：**
- 第一個參數為來源分支，其餘為目標分支
- 至少需要一個來源分支和一個目標分支

**否則：**
- 使用 AskUserQuestion 詢問使用者來源分支名稱
- 再使用 AskUserQuestion 詢問使用者目標分支名稱（可輸入多個，以空格或逗號分隔）

`moxa:scan-from-branch` 會自動：
- 偵測 remote（upstream 優先，否則 origin）
- 執行 `git fetch` 更新遠端資訊
- 驗證來源分支和各目標分支存在於 remote
- 對每個目標分支與來源分支進行單向比對
- 過濾非功能性 commits
- 產出單向同步狀態報告

### Step 2: 檢視報告並選擇同步目標

收到 `moxa:scan-from-branch` 的同步狀態報告後展示：

```
## 單向同步狀態報告

來源分支: source-branch

### target-A (3 commits 需要同步)
  abc1234 feat(api): add endpoint          ← from source-branch
  def5678 fix(auth): fix login             ← from source-branch
  ghi9012 refactor: optimize               ← from source-branch

### target-B (1 commit 需要同步)
  jkl3456 feat(ui): add dashboard          ← from source-branch

### target-C (0 commits - 已同步)
  ✓ 所有 commits 已同步

---
總結：來源 source-branch → 3 個目標分支中，2 個需要同步，1 個已完全同步
```

使用 AskUserQuestion 詢問：

```
以上是各目標分支的同步狀態。請選擇要執行同步的分支：

1. 全部需要同步的分支都執行
2. 只同步部分分支（請說明）
3. 需要排除部分 commits（請說明要排除的 commit hash）
```

如果使用者要排除 commits 或跳過分支，調整清單後再次確認。

### Step 3: 逐一執行 Cherry-Pick 同步

對每個需要同步的目標分支，觸發 `moxa:cherry-pick-sync` skill：

- 逐一傳入目標分支與對應的 commits 清單
- **重要：** 傳入 sync 分支命名格式為 `sync/from-<source>-to-<target>`（不使用預設的 `sync/to-<target>`）
- `moxa:cherry-pick-sync` 對每個分支會：
  1. 基於目標分支建立 `sync/from-<source>-to-<target>` 分支
  2. Cherry-pick commits（從最舊到最新）
  3. 衝突時中止並清理該分支，繼續處理下一個
  4. 成功後 push 分支
  5. 呼叫 `moxa:create-pr` 建立 MR（含 commit 表格）
  6. 切回原始分支

### 綜合報告

所有分支處理完畢後展示綜合報告：

```
## 單向 Sync 綜合結果

來源分支: source-branch

### ✅ 成功同步
| 目標分支 | Sync 分支 | Commits | MR |
|----------|-----------|---------|-----|
| target-A | sync/from-source-to-target-A | 3 | !123 |
| target-B | sync/from-source-to-target-B | 1 | !124 |

### ❌ 同步失敗（衝突）
| 目標分支 | 衝突 Commit | 需手動處理 |
|----------|-------------|-----------|
| (無) |

### 📊 統計
- 來源分支: source-branch
- 總計目標分支: 2
- 成功: 2
- 失敗: 0
- 已建立 MR: 2
```

## 內部技能

| 步驟 | Skill | 備註 |
|------|-------|------|
| 單向比對分支差異 | `moxa:scan-from-branch` | 驗證分支、單向比對 commits、過濾非功能 commits |
| 執行 cherry-pick | `moxa:cherry-pick-sync` | 逐一分支 cherry-pick commits、建立 sync 分支、處理衝突 |
| 建立 MR | `moxa:create-pr` | 建立 GitLab Merge Request |

## 使用範例

```bash
# 從 source 單向同步到多個目標分支
/sync-from switch-mds-g4000 switch-mds-g4100 switch-eis-series

# 從 source 同步到單一目標分支
/sync-from switch-mds-g4000 switch-mds-g4100

# 互動模式（會詢問來源和目標分支名稱）
/sync-from
```

## 注意事項

1. **單向同步**：只從來源分支流向目標分支，不反向比對
2. **工作目錄必須乾淨**：執行前需確保沒有未提交的變更
3. **衝突處理**：遇到衝突會停止該分支的同步，繼續處理下一個分支
4. **分支命名**：sync 分支使用 `sync/from-<source>-to-<target>` 格式，明確標示來源
5. **MR 格式**：使用固定模板，列出所有 cherry-pick 的 commits
6. **安全性**：不會修改任何現有分支的 commits，僅建立新的 sync 分支
7. **自動過濾**：自動排除 merge commits、release commits 等非功能性 commits
