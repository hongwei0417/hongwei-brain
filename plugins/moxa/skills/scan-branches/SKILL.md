---
name: moxa:scan-branches
allowed-tools: Bash(git:*), Bash(grep:*), AskUserQuestion
description: Compare multiple remote branches against the current branch to find missing commits. Validates branches exist on remote, compares commits between current branch and each target branch, and filters out non-functional commits. Produces a comprehensive sync status report. Triggers on "scan branches", "compare branches", "find branches to sync", or "branch diff".
---

# Scan Branches Skill

## Overview

比對多個遠端分支與當前分支的 commits 差異，產出完整的同步狀態報告。接收多個分支名稱，驗證其存在於 remote，逐一比較當前分支與各目標分支的 commit 差異，並自動過濾非功能性 commits。目的是確保所有 commits 都已同步，不會有缺少的狀況。

## When to Use

- 需要檢查多個分支的 commits 同步狀態
- 比對當前分支與多個目標分支的 commit 差異
- 產出完整的同步狀態報告
- 準備 cherry-pick sync 前的分析

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

### 3. 驗證各目標分支

逐一確認每個分支名稱存在於 remote：

```bash
# 檢查分支是否存在（支援帶或不帶 remote 前綴的名稱）
git branch -r | grep "$REMOTE/" | grep -v HEAD | grep "<branch-name>"
```

**如果某個分支不存在：**
- 通知使用者該分支不存在
- 列出類似名稱的分支供參考
- 使用 AskUserQuestion 詢問正確的分支名稱或是否跳過

### 4. 逐一比對 Commits

對每個目標分支，比對當前分支的 commits 差異：

```bash
# 取得當前分支名稱
CURRENT_BRANCH=$(git branch --show-current)

# 對每個目標分支比對
# 找出當前分支有但目標分支沒有的 commits
# 使用 cherry 比對（基於 patch 內容，避免重複計算已 cherry-pick 過的 commits）
git log --cherry-pick --right-only --no-merges --oneline $REMOTE/<target-branch>...$CURRENT_BRANCH
```

**比對說明：**
- 使用 `--cherry-pick` 過濾已經透過 cherry-pick 同步過的 commits（基於 patch-id 比對）
- 使用 `--right-only` 只顯示當前分支獨有的 commits
- 使用 `--no-merges` 排除 merge commits

### 5. 過濾非功能性 Commits

對每個分支的比對結果，自動排除以下類型的 commits：

```bash
git log --cherry-pick --right-only --no-merges --oneline $REMOTE/<target>...$CURRENT_BRANCH \
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

以結構化方式呈現所有目標分支的差異 commits：

```
## 分支同步狀態報告

來源分支: feature/my-feature

### switch-mds-g4000 (5 commits 需要同步)
  abc1234 feat(api): add new endpoint
  def5678 fix(auth): fix login issue
  ghi9012 refactor: optimize query
  jkl3456 feat(ui): add dashboard
  mno7890 fix(core): memory leak

### switch-mds-g4100 (2 commits 需要同步)
  abc1234 feat(api): add new endpoint
  jkl3456 feat(ui): add dashboard

### switch-eis-series (0 commits - 已同步)
  ✓ 所有 commits 已同步

---
總結：3 個分支中，2 個需要同步，1 個已完全同步
```

## Integration Note

當被 `/sync-branches` 命令呼叫時：
- 接收多個目標分支名稱
- 驗證各分支存在於 remote
- 回傳各分支的 commits 差異資訊
- 後續由使用者逐一選擇目標分支，交由 `moxa:cherry-pick-sync` skill 執行同步
