---
allowed-tools: Bash(diff:*), Bash(cp:*), Bash(ls:*), Bash(mkdir:*), Bash(cat:*), Bash(find:*), AskUserQuestion, Read, Write, Edit, Glob, Grep
description: Sync files between openspec/ and libs/switch/.openspec/ — ensures both directories contain all files with consistent content, resolving conflicts interactively
---

# Sync OpenSpec - 雙向檔案同步工作流程

同步 `openspec/` 與 `libs/switch/.openspec/` 兩個目錄的檔案，確保兩邊都涵蓋所有檔案且內容一致。單邊獨有的檔案自動複製到另一邊，內容衝突時展示 diff 並詢問使用者如何合併。

## 目錄定義

- **目錄 A**: `openspec/` （專案根目錄下）
- **目錄 B**: `libs/switch/.openspec/`

## 前置檢查

1. 確認兩個目錄都存在，若不存在則建立缺少的目錄
2. 列出兩個目錄的完整檔案清單（包含子目錄，使用相對路徑）

## 執行步驟

### Step 1: 掃描兩邊檔案

使用 `find` 列出兩個目錄中所有檔案的相對路徑：

```bash
# 列出目錄 A 的所有檔案（相對路徑）
(cd openspec && find . -type f | sort)

# 列出目錄 B 的所有檔案（相對路徑）
(cd libs/switch/.openspec && find . -type f | sort)
```

將檔案分為三類：
- **僅存在於 A**：只在 `openspec/` 中有的檔案
- **僅存在於 B**：只在 `libs/switch/.openspec/` 中有的檔案
- **兩邊都有**：兩個目錄都有的同名檔案

### Step 2: 展示同步狀態報告

整理並展示報告：

```
## OpenSpec 同步狀態報告

### 📁 僅存在於 openspec/ (N 個檔案)
  - path/to/file1.yaml
  - path/to/file2.json

### 📁 僅存在於 libs/switch/.openspec/ (N 個檔案)
  - path/to/file3.yaml

### 🔄 兩邊都有的檔案 (N 個檔案)
  ✅ path/to/same.yaml — 內容一致
  ⚠️ path/to/conflict.yaml — 內容不同

### 📊 統計
- openspec/ 獨有: X 個檔案（將複製到 libs/switch/.openspec/）
- libs/switch/.openspec/ 獨有: Y 個檔案（將複製到 openspec/）
- 內容一致: Z 個檔案（無需處理）
- 內容衝突: W 個檔案（需要處理）
```

### Step 3: 處理單邊獨有檔案

對於僅存在於一邊的檔案，自動複製到另一邊：

- **僅存在於 A 的檔案** → 複製到 B 對應路徑（自動建立子目錄）
- **僅存在於 B 的檔案** → 複製到 A 對應路徑（自動建立子目錄）

複製時使用 `cp` 並保留檔案內容。如果目標路徑的父目錄不存在，先用 `mkdir -p` 建立。

### Step 4: 處理衝突檔案

對每個內容不同的檔案，逐一處理：

1. **展示 diff**：使用 `diff` 命令顯示兩邊的差異

```bash
diff openspec/<file> libs/switch/.openspec/<file>
```

2. **使用 AskUserQuestion 詢問使用者**：

```
檔案 <file> 存在內容差異：

（展示 diff 摘要）

請選擇處理方式：
1. 使用 openspec/ 的版本（覆蓋 libs/switch/.openspec/）
2. 使用 libs/switch/.openspec/ 的版本（覆蓋 openspec/）
3. 手動合併（我會協助整合兩邊內容）
4. 跳過此檔案
```

3. **根據使用者選擇執行**：
   - 選擇 1 → 用 A 的內容覆蓋 B
   - 選擇 2 → 用 B 的內容覆蓋 A
   - 選擇 3 → 讀取兩邊檔案內容，智慧合併後寫入兩邊（合併前先展示合併結果，確認後再寫入）
   - 選擇 4 → 不做任何處理，繼續下一個檔案

### Step 5: 綜合報告

所有檔案處理完畢後展示：

```
## OpenSpec 同步結果

### ✅ 已複製
| 檔案 | 方向 |
|------|------|
| file1.yaml | openspec/ → libs/switch/.openspec/ |
| file3.yaml | libs/switch/.openspec/ → openspec/ |

### 🔄 衝突已解決
| 檔案 | 處理方式 |
|------|----------|
| conflict.yaml | 使用 openspec/ 版本 |

### ⏭️ 已跳過
| 檔案 | 原因 |
|------|------|
| (無) |

### 📊 統計
- 複製: X 個檔案
- 衝突解決: Y 個檔案
- 跳過: Z 個檔案
- 無需處理: W 個檔案
```

## 注意事項

1. **非破壞性**：所有操作僅為複製或覆蓋檔案，不會刪除任何檔案
2. **衝突需確認**：內容不同的檔案一定會詢問使用者，不會自動覆蓋
3. **保留結構**：子目錄結構會完整保留
4. **版控友善**：同步後的變更可透過 `git diff` 檢視，使用者可決定是否 commit
