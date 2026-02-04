---
name: moxa:scan-from-branch
allowed-tools: Bash(git:*), Bash(grep:*), AskUserQuestion
description: Compare a single source branch against multiple target branches in one direction to find commits the targets are missing. Validates branches exist on remote, performs one-way comparison (source → each target), deduplicates by commit hash, and produces a per-target sync status report. Triggers on "scan from branch", "one-way compare", "find missing commits from source", or "compare source to targets".
---

# Scan From Branch Skill

## Overview

單向比對一個來源分支與多個目標分支的 commits 差異，產出每個目標分支缺少的 commits 報告。接收一個來源分支和 N 個目標分支，對每個目標分支找出來源分支有但目標分支沒有的 commits。

**注意：** 此技能為單向比對。只找出來源分支有但目標分支沒有的 commits，不會反向比對。

## When to Use

- 需要從一個來源分支同步 commits 到多個目標分支
- 單向比對：來源 → 目標（不反向）
- 產出每個目標分支缺少的 commits 報告
- 準備單向 cherry-pick sync 前的分析

## Process

### 1. 偵測 Remote

自動偵測使用的 remote：

```bash
# 優先使用 upstream，沒有則使用 origin
if git remote get-url upstream &>/dev/null; then
  REMOTE="upstream"
else
  REMOTE="origin"
fi
echo "使用 Remote: $REMOTE"
```

### 2. 更新遠端資訊

```bash
git fetch $REMOTE --prune
```

### 3. 驗證各分支

逐一確認來源分支和所有目標分支存在於 remote：

```bash
# 檢查分支是否存在（支援帶或不帶 remote 前綴的名稱）
git branch -r | grep "$REMOTE/" | grep -v HEAD | grep "<branch-name>"
```

**如果某個分支不存在：**
- 通知使用者該分支不存在
- 列出類似名稱的分支供參考
- 使用 AskUserQuestion 詢問正確的分支名稱或是否跳過

### 4. 單向比對 Commits

對每個目標分支 T，與來源分支 S 比對，找出 T 缺少的 commits：

```bash
# 找出來源分支 S 有但目標分支 T 沒有的 commits
# 即：T 缺少的、來自 S 的 commits
git log --cherry-pick --right-only --no-merges --oneline $REMOTE/T...$REMOTE/S
```

**比對說明：**
- 使用 `--cherry-pick` 過濾已經透過 cherry-pick 同步過的 commits（基於 patch-id 比對）
- 使用 `--right-only` 只顯示右側分支（S，即來源）獨有的 commits
- 使用 `--no-merges` 排除 merge commits
- 這表示：「來源 S 有但目標 T 沒有的 commits」= T 缺少的 commits

**範例（來源 A，目標 B, C）：**
```
比對 A → B: B 缺少來自 A 的 commits → [commit1, commit2]
比對 A → C: C 缺少來自 A 的 commits → [commit3]
```

### 5. 過濾非功能性 Commits

對比對結果，自動排除以下類型的 commits：

```bash
# 在每次 git log 比對時直接過濾
git log --cherry-pick --right-only --no-merges --oneline $REMOTE/T...$REMOTE/S \
  | grep -viE '^[a-f0-9]+ (Merge branch|Merge remote|release[:(]|bump version|chore\(release\)|v[0-9]+\.[0-9]+)'
```

**過濾的 commit 類型：**
- `Merge branch ...` — merge commits
- `Merge remote ...` — remote merge commits
- `release: ...` / `release(...)` — release commits
- `bump version` — 版本升級 commits
- `chore(release): ...` — release 相關 chore commits
- `v1.0.0` 等版本號開頭的 commits

### 6. 輸出綜合報告

以結構化方式呈現每個目標分支缺少的 commits：

```
## 單向同步狀態報告

來源分支: <source-branch>

### target-B (2 commits 需要同步)
  abc1234 feat(api): add endpoint          ← from <source-branch>
  def5678 fix(auth): fix login             ← from <source-branch>

### target-C (1 commit 需要同步)
  ghi9012 refactor: optimize               ← from <source-branch>

### target-D (0 commits - 已同步)
  ✓ 所有 commits 已同步

---
總結：來源 <source-branch> → 3 個目標分支中，2 個需要同步，1 個已完全同步
```

**報告格式要求：**
- 標題明確標示來源分支
- 每個目標分支一個區塊，標題顯示分支名稱和缺少的 commit 數量
- 每個 commit 標註來源分支（`← from <source-branch>`）
- 已完全同步的分支顯示 ✓ 標記
- 底部總結統計

## Integration Note

當被 `/sync-from` 命令呼叫時：
- 接收一個來源分支名稱和多個目標分支名稱
- 驗證各分支存在於 remote
- 執行單向比對（來源 → 每個目標）
- 回傳每個目標分支缺少的 commits 清單
- 後續由使用者選擇要同步的分支，交由 `moxa:cherry-pick-sync` skill 執行同步
