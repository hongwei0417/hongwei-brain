---
allowed-tools: Bash(git:*), AskUserQuestion, Skill
argument-hint: <branch1> <branch2> [branch3...]
description: Multi-directional sync — compare commits across multiple branches pairwise and cherry-pick sync missing commits with automatic MR creation
---

# Sync Branches - 多向 Cherry-Pick 同步工作流程

多向比對多個遠端分支的 commits 差異，找出每個分支缺少的 commits 並標註來源。對需要同步的分支逐一執行 cherry-pick 並建立 MR。

**所有輸入分支地位平等，互相比對。不依賴「當前分支」作為來源。**

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
┌──────────────────────────────────────────────────────────────┐
│       /sync-branches <branch1> <branch2> [branch3...]        │
└───────────────────────┬──────────────────────────────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 1: 多向比對       │
           │  A vs B, A vs C         │
           │  B vs A, B vs C         │
           │  C vs A, C vs B         │
           │  → 聚合每個分支缺少的   │
           │    commits + 去重標註   │
           └────────────┬────────────┘
                        │
           ┌────────────▼────────────┐
           │  Step 2: 展示同步報告   │
           │  A 缺: X,Y (from B,C)  │
           │  B 缺: Z (from A)      │
           │  C: 已同步             │
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

### Step 1: 多向比對各分支 Commits 差異

觸發 `moxa:scan-branches` skill。

**分支名稱來源：**

**如果 `$ARGUMENTS` 有提供分支名稱：**
- 直接使用提供的分支名稱（以空格分隔多個分支）

**否則：**
- 使用 AskUserQuestion 詢問使用者要比對的分支名稱（可輸入多個，以空格或逗號分隔）

`moxa:scan-branches` 會自動：
- 偵測 remote（upstream 優先，否則 origin）
- 執行 `git fetch` 更新遠端資訊
- 驗證各分支存在於 remote
- 對每個分支與所有其他分支進行 pairwise 比對
- 聚合每個分支缺少的 commits，按 commit hash 去重
- 標註每個 commit 的來源分支
- 過濾非功能性 commits
- 產出綜合同步狀態報告

### Step 2: 檢視報告並選擇同步目標

收到 `moxa:scan-branches` 的同步狀態報告後展示：

```
## 分支同步狀態報告

### branch-A (3 commits 需要同步)
  abc1234 feat(api): add endpoint          ← from branch-B
  def5678 fix(auth): fix login             ← from branch-B, branch-C
  ghi9012 refactor: optimize               ← from branch-C

### branch-B (1 commit 需要同步)
  jkl3456 feat(ui): add dashboard          ← from branch-A

### branch-C (0 commits - 已同步)
  ✓ 所有 commits 已同步

---
總結：3 個分支中，2 個需要同步，1 個已完全同步
```

使用 AskUserQuestion 詢問：

```
以上是各分支的同步狀態。請選擇要執行同步的分支：

1. 全部需要同步的分支都執行
2. 只同步部分分支（請說明）
3. 需要排除部分 commits（請說明要排除的 commit hash）
```

如果使用者要排除 commits 或跳過分支，調整清單後再次確認。

### Step 3: 逐一執行 Cherry-Pick 同步

對每個需要同步的分支，觸發 `moxa:cherry-pick-sync` skill：

- 逐一傳入目標分支與對應的聚合 commits 清單（含來源標註）
- `moxa:cherry-pick-sync` 對每個分支會：
  1. 基於目標分支建立 `sync/to-<target>` 分支
  2. Cherry-pick 聚合 commits（從最舊到最新）
  3. 衝突時中止並清理該分支，繼續處理下一個
  4. 成功後 push 分支
  5. 呼叫 `moxa:create-pr` 建立 MR（含來源分支標註的 commit 表格）
  6. 切回原始分支

### 綜合報告

所有分支處理完畢後展示綜合報告：

```
## Cherry-Pick Sync 綜合結果

### ✅ 成功同步
| 目標分支 | Sync 分支 | Commits | MR |
|----------|-----------|---------|-----|
| branch-A | sync/to-branch-A | 3 | !123 |
| branch-B | sync/to-branch-B | 1 | !124 |

### ❌ 同步失敗（衝突）
| 目標分支 | 衝突 Commit | 需手動處理 |
|----------|-------------|-----------|
| (無) |

### 📊 統計
- 總計目標分支: 2
- 成功: 2
- 失敗: 0
- 已建立 MR: 2
```

## 內部技能

| 步驟 | Skill | 備註 |
|------|-------|------|
| 多向比對分支差異 | `moxa:scan-branches` | 驗證分支、pairwise 比對 commits、去重標註來源、過濾非功能 commits |
| 執行 cherry-pick | `moxa:cherry-pick-sync` | 逐一分支 cherry-pick 聚合 commits、建立 sync 分支、處理衝突 |
| 建立 MR | `moxa:create-pr` | 建立 GitLab Merge Request |

## 使用範例

```bash
# 多向比對三個分支（互相比對，找出各自缺少的 commits）
/sync-branches switch-mds-g4000 switch-mds-g4100 switch-eis-series

# 比對兩個分支（互相比對）
/sync-branches switch-mds-g4000 switch-mds-g4100

# 互動模式（會詢問要比對的分支名稱）
/sync-branches
```

## 注意事項

1. **所有分支地位平等**：不依賴當前分支作為來源，所有輸入分支互相比對
2. **工作目錄必須乾淨**：執行前需確保沒有未提交的變更
3. **衝突處理**：遇到衝突會停止該分支的同步，繼續處理下一個分支
4. **分支命名**：sync 分支使用 `sync/to-<target>` 格式（因來源為多個分支）
5. **MR 格式**：使用固定模板，列出所有 cherry-pick 的 commits 及其來源分支
6. **安全性**：不會修改任何現有分支的 commits，僅建立新的 sync 分支
7. **自動過濾**：自動排除 merge commits、release commits 等非功能性 commits
8. **去重機制**：相同 commit 出現在多個來源分支時只 cherry-pick 一次
