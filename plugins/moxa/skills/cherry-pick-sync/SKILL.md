---
name: moxa:cherry-pick-sync
allowed-tools: Bash(git:*), AskUserQuestion, Skill
description: Execute cherry-pick sync from current branch to target branches. Creates sync branches, cherry-picks selected commits, handles conflicts by stopping and notifying, and triggers MR creation. Triggers on "cherry-pick sync", "sync commits", "cherry-pick to branches", or "sync branches".
---

# Cherry-Pick Sync Skill

## Overview

執行 cherry-pick 同步作業：基於目標分支建立 sync 分支，cherry-pick 選定的 commits，處理衝突（停止並通知），並建立 GitLab MR。

## When to Use

- 需要將當前分支的 commits 同步到其他分支
- Cherry-pick 多個 commits 到多個目標分支
- 建立 sync MR

## Process

### 1. 接收參數

從 `/sync-branches` 命令接收：
- 目標分支清單及各分支對應的 commits
- 來源分支名稱
- Remote 名稱

### 2. 記錄當前狀態

```bash
# 記錄當前分支，以便完成後切回
ORIGINAL_BRANCH=$(git branch --show-current)
REMOTE="<detected remote>"
```

### 3. 對每個目標分支執行 Cherry-Pick

依序處理每個目標分支：

#### 3.1 建立 Sync 分支

```bash
TARGET_BRANCH="<target-branch>"
SOURCE_BRANCH="$ORIGINAL_BRANCH"

# 分支命名格式：sync/<source>-to-<target>
SYNC_BRANCH="sync/${SOURCE_BRANCH}-to-${TARGET_BRANCH}"

# 基於目標分支的最新狀態建立 sync 分支
git checkout -b "$SYNC_BRANCH" "$REMOTE/$TARGET_BRANCH"
```

**如果分支已存在：**
- 通知使用者分支已存在
- 詢問是否刪除重建或跳過該分支

#### 3.2 執行 Cherry-Pick

逐一 cherry-pick 選定的 commits：

```bash
# 依照 commit 順序（從最舊到最新）執行
for COMMIT_HASH in <commits-oldest-to-newest>; do
  git cherry-pick "$COMMIT_HASH"
done
```

#### 3.3 衝突處理

**遇到 conflict 時立即停止：**

```bash
# 如果 cherry-pick 失敗
if ! git cherry-pick "$COMMIT_HASH"; then
  # 中止 cherry-pick
  git cherry-pick --abort

  # 刪除 sync 分支
  git checkout "$ORIGINAL_BRANCH"
  git branch -D "$SYNC_BRANCH"

  # 通知使用者
  echo "Cherry-pick 衝突！"
  echo "衝突 commit: $COMMIT_HASH"
  echo "目標分支: $TARGET_BRANCH"
  echo "已中止此分支的同步，繼續處理下一個分支"
fi
```

**衝突報告格式：**
```
⚠️ Cherry-pick 衝突

分支: switch-mds-g4000
衝突 Commit: abc1234 feat(api): add new endpoint
狀態: 已中止，sync 分支已刪除

請手動處理：
1. git checkout -b sync/<source>-to-<target> <remote>/<target>
2. git cherry-pick <commit-hash>
3. 解決衝突後 git cherry-pick --continue
```

#### 3.4 Push Sync 分支

Cherry-pick 全部成功後推送到 origin（使用者自己的 remote，即使分支是基於 upstream 建立的）：

```bash
# 永遠 push 到 origin（自己的 remote），後續由 create-pr 處理跨專案 MR
git push -u origin "$SYNC_BRANCH"
```

#### 3.5 建立 MR

使用 `moxa:create-pr` skill 建立 MR，傳入以下設定：

**MR 設定：**
- Source branch: `sync/<source>-to-<target>`
- Target branch: `<target-branch>`
- Title: `sync: cherry-pick commits from <source> to <target>`
- Description: 固定格式模板

**MR Description 模板：**
```markdown
## Sync Cherry-Pick

從 `<source-branch>` 同步以下 commits 到 `<target-branch>`：

| Commit | Message |
|--------|---------|
| abc1234 | feat(api): add new endpoint |
| def5678 | fix(auth): fix login issue |
| ghi9012 | refactor: optimize query |

---
*由 moxa sync-branches 自動建立*
```

### 4. 切回原始分支

所有目標分支處理完畢後：

```bash
git checkout "$ORIGINAL_BRANCH"
```

### 5. 綜合報告

```
## Cherry-Pick Sync 結果

### ✅ 成功同步
| 目標分支 | Sync 分支 | Commits | MR |
|----------|-----------|---------|-----|
| switch-mds-g4000 | sync/feature-x-to-switch-mds-g4000 | 5 | !123 |
| switch-mds-g4100 | sync/feature-x-to-switch-mds-g4100 | 3 | !124 |

### ❌ 同步失敗（衝突）
| 目標分支 | 衝突 Commit | 需手動處理 |
|----------|-------------|-----------|
| switch-eis | abc1234 feat(api): add new endpoint | 是 |

### 📊 統計
- 總計目標分支: 3
- 成功: 2
- 失敗: 1
- 已建立 MR: 2
```

## Safety Checks

- 確保工作目錄乾淨（無未提交的變更）
- Cherry-pick 前確認 sync 分支名稱不衝突
- 衝突時安全中止並清理
- 完成後一定切回原始分支
- 不會修改任何現有分支的 commits

## Error Handling

**工作目錄不乾淨：**
```
錯誤：工作目錄有未提交的變更
請先 commit 或 stash 您的變更後再執行同步
```

**Push 失敗：**
```
錯誤：Push 失敗
分支: sync/<source>-to-<target>
請檢查網路連線和 remote 權限
```

**MR 建立失敗：**
- 記錄錯誤但繼續處理下一個分支
- 在最終報告中標示 MR 建立失敗的分支

## Integration Note

當被 `/sync-branches` 命令呼叫時：
- 接收 `moxa:scan-branches` 的分析結果
- 使用者已確認的 commits 清單
- 依序處理每個目標分支
- 呼叫 `moxa:create-pr` 建立 MR
- 回傳綜合結果報告
