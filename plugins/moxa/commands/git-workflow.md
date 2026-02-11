---
allowed-tools: Bash(git:*), Read, Grep, Glob, AskUserQuestion, Skill
argument-hint: [--full | --step <step-name>]
description: Integrated Git workflow completing create-branch → commit → create-pr in one flow
---

# Git Flow - 整合性工作流程

執行 Git 開發工作流程: $ARGUMENTS

## 當前倉庫狀態

- 專案目錄: !`basename $(pwd)`
- 當前分支: !`git branch --show-current`
- Git 狀態: !`git status --short`
- Remote 資訊: !`git remote -v`

## 執行模式

根據 `$ARGUMENTS` 決定執行模式：

### 模式判斷

**如果 `$ARGUMENTS` 包含 `--full` 或為空：**
- 執行「全流程模式」

**如果 `$ARGUMENTS` 包含 `--step`：**
- 執行「單一任務模式」，直接執行指定的步驟

**否則（無參數）：**
- 使用 AskUserQuestion 詢問用戶選擇哪種模式

## 模式一：全流程模式

流程順序：**Create Branch → Commit → Create PR**

### 第一階段：收集所有設定

在開始執行前，一次性詢問所有流程設定：

**使用 AskUserQuestion 詢問（支援多選）：**

```
請選擇要執行的步驟：

□ Create Branch - 建立新分支（含 worktree 選項）
□ Commit - 提交變更
□ Create PR - 建立 GitLab Merge Request
```

**針對各步驟的額外設定：**

**如果選擇 Create Branch：**
- 詢問分支描述（或從程式碼變更自動產生）
- 詢問是否需要 worktree

**如果選擇 Create PR：**
- 偵測是否為 fork 場景（origin + upstream）
- 詢問 MR 目標 remote（origin 或 upstream）
- 詢問目標分支：
  ```
  請選擇合併目標分支：

  1. main
  2. develop
  3. <當前分支切出的來源分支>
  4. 自訂輸入
  ```

### 第二階段：依序執行（一次完成，不中斷）

根據第一階段收集的設定，依序執行所選步驟，中間不會停止：

**1. Create Branch（如果選擇）**
- 觸發 `moxa:create-branch` skill
- 使用第一階段收集的設定
- 完成後立即進入下一步

**2. Commit（如果選擇）**
- 觸發 `moxa:commit` skill
- 該技能會自動判斷是否需要切分成多個 commit 或合併為一個
- 完成後立即進入下一步

**3. Create PR（如果選擇）**
- 觸發 `moxa:create-pr` skill
- 使用第一階段收集的目標 remote 和目標分支設定

### 第三階段：報告結果

執行完成後，彙整報告：
- 各步驟執行結果
- 建立的分支名稱（如有）
- Commit 資訊（如有）
- MR 連結（如有）

## 模式二：單一任務模式

**如果有 `--step` 參數：**
- 直接執行指定步驟
- 可用值：`create-branch`, `commit`, `create-pr`

**如果無參數且選擇單一任務：**
使用 AskUserQuestion 詢問要執行哪個任務：

```
選項：
1. Create Branch - 建立新分支（含 worktree 選項）
2. Commit - 提交變更
3. Create PR - 建立 GitLab Merge Request
```

根據選擇執行對應步驟。

## 內部技能

此命令使用以下內部 skills：

| 步驟 | Skill | 備註 |
|------|-------|------|
| Create Branch | `moxa:create-branch` | 建立分支並可選 worktree |
| Commit | `moxa:commit` | 自動判斷 commit 切分策略 |
| Create PR | `moxa:create-pr` | 支援 fork 跨專案 MR |

## 使用範例

```bash
# 互動式選擇模式
/git-workflow

# 全流程模式（先問設定，再一次執行）
/git-workflow --full

# 單一任務：建立分支
/git-workflow --step create-branch

# 單一任務：提交
/git-workflow --step commit

# 單一任務：建立 PR
/git-workflow --step create-pr
```

## 流程圖

```
┌─────────────────────────────────────────────────────────┐
│                      /git-workflow --full                    │
└─────────────────────┬───────────────────────────────────┘
                      │
         ┌────────────▼────────────┐
         │   第一階段：收集設定     │
         │                         │
         │  □ 選擇要執行的步驟      │
         │  □ Create Branch 設定   │
         │  □ Create PR 設定       │
         │    - 目標 remote        │
         │    - 目標分支           │
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │   第二階段：依序執行     │
         │   （一次完成，不中斷）   │
         │                         │
         │  1. Create Branch ─────→│
         │  2. Commit ────────────→│
         │  3. Create PR           │
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │   第三階段：報告結果     │
         └─────────────────────────┘
```

## 注意事項

1. **Git 操作不中斷**：Create Branch → Commit → Create PR 會一次完成
2. **分支保護**：不會在 main/master/develop 分支上直接提交
3. **Fork 偵測**：自動偵測是否為 fork 場景
4. **目標分支**：Create PR 支援選擇任意目標分支，不限於 main
