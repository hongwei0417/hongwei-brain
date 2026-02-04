---
name: moxa:scan-branches
allowed-tools: Bash(git:*), Bash(grep:*), Bash(ls:*), Bash(basename:*), AskUserQuestion
description: Scan and compare remote branches for cherry-pick sync. Searches branches by keyword (project names from apps/switch or switch-related names), compares commits between current branch and target branches, and filters out non-functional commits. Triggers on "scan branches", "compare branches", "find branches to sync", or "branch diff".
---

# Scan Branches Skill

## Overview

搜尋遠端分支並比對 commits 差異，用於 cherry-pick sync 工作流程。支援以關鍵字搜尋 apps/switch 專案相關分支，比較當前分支與目標分支的 commit 差異，並自動過濾非功能性 commits。

## When to Use

- 需要找出哪些分支缺少當前分支的 commits
- 搜尋 switch 相關專案分支
- 比對分支間的 commit 差異
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

### 3. 搜尋分支

#### 3a. 有指定關鍵字時

直接使用該關鍵字搜尋：

```bash
git branch -r | grep "$REMOTE/" | grep -v HEAD | grep -i "<keyword>"
```

#### 3b. 無指定關鍵字時（預設行為）

自動從 `apps/switch/` 目錄取得專案名稱，並搜尋 `switch` 相關分支：

```bash
# Step 1: 掃描 apps/switch/ 底下的專案目錄名稱
# 例如：mds-g4000, eis-series, sds-100 等
PROJECT_NAMES=$(ls -d apps/switch/*/ 2>/dev/null | xargs -I {} basename {})

# Step 2: 用每個專案名稱作為關鍵字搜尋遠端分支
for NAME in $PROJECT_NAMES; do
  git branch -r | grep "$REMOTE/" | grep -v HEAD | grep -i "$NAME"
done

# Step 3: 同時搜尋包含 switch 關鍵字的分支
git branch -r | grep "$REMOTE/" | grep -v HEAD | grep -i "switch"

# Step 4: 合併所有結果並去重
# 將 Step 2 + Step 3 的結果合併，排除重複項目
```

**搜尋策略：**
- 預設自動掃描 `apps/switch/` 底下的專案名稱作為搜尋關鍵字
- 同時搜尋包含 `switch` 關鍵字的分支
- 合併去重後排除 HEAD 指標
- 關鍵字不區分大小寫
- 排除當前分支本身

### 4. 列出分支供選擇

使用 AskUserQuestion 讓使用者選擇要比對的分支（支援多選）：

```
找到以下符合的遠端分支：

□ switch-mds-g4000
□ switch-mds-g4100
□ switch-eis-series
□ ...

請選擇要比對的分支（可多選）：
```

### 5. 比對 Commits

對每個選擇的目標分支，比對當前分支的 commits 差異：

```bash
# 取得當前分支名稱
CURRENT_BRANCH=$(git branch --show-current)

# 找出當前分支有但目標分支沒有的 commits
# 使用 cherry 比對（基於 patch 內容，避免重複計算已 cherry-pick 過的 commits）
git log --cherry-pick --right-only --no-merges --oneline $REMOTE/<target-branch>...$CURRENT_BRANCH
```

**比對說明：**
- 使用 `--cherry-pick` 過濾已經透過 cherry-pick 同步過的 commits（基於 patch-id 比對）
- 使用 `--right-only` 只顯示當前分支獨有的 commits
- 使用 `--no-merges` 排除 merge commits

### 6. 過濾非功能性 Commits

自動排除以下類型的 commits：

```bash
# 過濾條件（排除）：
# 1. Merge commits（--no-merges 已處理）
# 2. Release commits（commit message 包含 release 相關關鍵字）
# 3. Version bump commits

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

### 7. 輸出結果

以結構化方式呈現每個目標分支的差異 commits：

```
## 分支比對結果

### switch-mds-g4000 (5 commits 需要同步)
  abc1234 feat(api): add new endpoint
  def5678 fix(auth): fix login issue
  ghi9012 refactor: optimize query
  jkl3456 feat(ui): add dashboard
  mno7890 fix(core): memory leak

### switch-mds-g4100 (3 commits 需要同步)
  abc1234 feat(api): add new endpoint
  def5678 fix(auth): fix login issue
  ghi9012 refactor: optimize query

### switch-eis-series (0 commits - 已同步)
  ✓ 所有 commits 已同步
```

## Integration Note

當被 `/sync-branches` 命令呼叫時：
- 接收關鍵字參數用於分支搜尋
- 回傳結構化的分支與 commits 差異資訊
- 後續交由 `moxa:cherry-pick-sync` skill 執行同步
