---
name: scan-branches
allowed-tools: Bash(git:*), Bash(grep:*), AskUserQuestion
description: Compare multiple remote branches against each other pairwise to find missing commits per branch. Validates branches exist on remote, performs multi-directional comparison (each branch vs all others), deduplicates by commit hash, annotates source branches, and produces a comprehensive sync status report. Triggers on "scan branches", "compare branches", "find branches to sync", or "branch diff".
---

# Scan Branches Skill

## Overview

多向比對多個遠端分支的 commits 差異，產出完整的同步狀態報告。接收 N 個分支名稱，對每個分支與其他所有分支進行 pairwise 比較，聚合每個分支缺少的 commits，去重並標註來源分支。目的是確保所有分支間的 commits 都已同步。

**注意：** 此技能不使用「當前分支」作為基準。所有輸入的分支地位平等，互相比對。

## When to Use

- 需要檢查多個分支之間的 commits 同步狀態
- 多向比對：每個分支與所有其他分支互相比對
- 產出完整的同步狀態報告（每個分支缺少哪些 commits）
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
# 同時拉取同步點 tags
git fetch $REMOTE 'refs/tags/sync-point/*:refs/tags/sync-point/*' 2>/dev/null || true
```

### 3. 驗證各分支

逐一確認每個分支名稱存在於 remote：

```bash
# 檢查分支是否存在（支援帶或不帶 remote 前綴的名稱）
git branch -r | grep "$REMOTE/" | grep -v HEAD | grep "<branch-name>"
```

**如果某個分支不存在：**
- 通知使用者該分支不存在
- 列出類似名稱的分支供參考
- 使用 AskUserQuestion 詢問正確的分支名稱或是否跳過

### 4. 多向 Pairwise 比對 Commits

對每個分支 T，與所有其他分支 S 逐一比對，找出 T 缺少的 commits。

**每對 (S, T) 比對前，先檢查同步點 Tag：**

```bash
# 對每一對 (T, S)：
SYNC_TAG="sync-point/from-${S}-to-${T}"
git fetch $REMOTE "refs/tags/${SYNC_TAG}:refs/tags/${SYNC_TAG}" 2>/dev/null

if git rev-parse "$SYNC_TAG" &>/dev/null; then
  # 有同步點：取得 tag 的 commit 日期，只比對此日期之後的 commits
  SYNC_DATE=$(git log -1 --format=%cI "$SYNC_TAG")
  echo "找到同步點: $SYNC_TAG (${SYNC_DATE})"

  # 縮小範圍：只查找同步點之後的 commits
  git log --cherry-pick --right-only --no-merges --oneline \
    --after="$SYNC_DATE" $REMOTE/$T...$REMOTE/$S
else
  # 無同步點：完整比對
  git log --cherry-pick --right-only --no-merges --oneline $REMOTE/$T...$REMOTE/$S
fi
```

**比對說明：**
- 使用 `--cherry-pick` 過濾已經透過 cherry-pick 同步過的 commits（基於 patch-id 比對）
- 使用 `--right-only` 只顯示右側分支（S）獨有的 commits
- 使用 `--no-merges` 排除 merge commits
- 這表示：「S 有但 T 沒有的 commits」= T 缺少的 commits
- **有同步點 tag 時**：使用 `--after` 限制只比對同步點之後的 commits
- **無同步點 tag 時**：回退到完整比對（相容舊行為）

**範例（3 個分支 A, B, C）：**
```
# 有同步點 sync-point/from-B-to-A (2025-01-15)
比對 A vs B: A 缺少來自 B 的 commits（2025-01-15 之後）→ [commit5]

# 無同步點
比對 A vs C: A 缺少來自 C 的 commits（完整比對）→ [commit5, commit6]

# 有同步點 sync-point/from-A-to-B (2025-01-10)
比對 B vs A: B 缺少來自 A 的 commits（2025-01-10 之後）→ [commit2]

比對 B vs C: B 缺少來自 C 的 commits（完整比對）→ [commit2, commit6]
比對 C vs A: C 缺少來自 A 的 commits（完整比對）→ [commit1, commit3]
比對 C vs B: C 缺少來自 B 的 commits（完整比對）→ [commit1, commit3]
```

### 5. 聚合與去重

對每個目標分支 T，合併來自所有其他分支的缺少 commits：

1. **收集**：收集所有 (T, S) 對的結果
2. **去重**：按 commit hash 去重（相同 hash 只保留一筆）
3. **標註來源**：如果同一個 commit 在多個來源分支中出現，列出所有來源分支
4. **排序**：按 commit 時間排序（從最舊到最新）

**去重範例：**
```
A 缺少: commit5 (from B), commit5 (from C), commit6 (from C)
→ 去重後: commit5 (from B, C), commit6 (from C)
```

### 6. 過濾非功能性 Commits

對去重後的結果，自動排除以下類型的 commits：

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

### 7. 輸出綜合報告

以結構化方式呈現每個分支缺少的 commits 及來源：

```
## 分支同步狀態報告

### branch-A (2 commits 需要同步)
  🏷️ 同步點: from-B-to-A (2025-01-15), from-C-to-A: 無
  abc1234 feat(api): add endpoint          ← from branch-B, branch-C
  def5678 fix(auth): fix login             ← from branch-C

### branch-B (1 commit 需要同步)
  🏷️ 同步點: from-A-to-B (2025-01-10)
  ghi9012 feat(ui): add dashboard          ← from branch-A

### branch-C (0 commits - 已同步)
  🏷️ 同步點: from-A-to-C (2025-01-12), from-B-to-C (2025-01-12)
  ✓ 所有 commits 已同步

---
總結：3 個分支中，2 個需要同步，1 個已完全同步
```

**報告格式要求：**
- 每個分支一個區塊，標題顯示分支名稱和缺少的 commit 數量
- 每個 commit 標註來源分支（`← from branch-X, branch-Y`）
- 已完全同步的分支顯示 ✓ 標記
- 底部總結統計

## Integration Note

當被 `/sync-branches` 命令呼叫時：
- 接收多個分支名稱（所有分支地位平等，無「來源分支」概念）
- 驗證各分支存在於 remote
- 執行多向 pairwise 比對
- 回傳每個分支缺少的 commits 清單（含來源標註）
- 後續由使用者選擇要同步的分支，交由 `moxa:cherry-pick-sync` skill 執行同步
