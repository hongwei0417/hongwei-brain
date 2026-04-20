#!/usr/bin/env bash
#
# copy-dirs.sh
# 複製來源目錄底下指定的資料夾或檔案到目的目錄。
# 若來源目錄底下沒有該項目則跳過。
#
# 使用方式:
#   ./copy-dirs.sh <來源目錄> <目的目錄>
#
# 範例:
#   ./copy-dirs.sh ~/projects/foo ~/backup/foo
#

set -euo pipefail

# ===== 要複製的項目清單 — 資料夾或檔案皆可 (可自行增減) =====
ITEMS_TO_COPY=(
    ".claude"
    ".planning"
    ".env"
)
# ==========================================

# --- 顏色輸出 (若 terminal 不支援則自動關閉) ---
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    NC=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
fi

log_info()  { echo "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo "${YELLOW}[SKIP]${NC}  $*"; }
log_error() { echo "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    cat <<EOF
使用方式: $(basename "$0") <來源目錄> <目的目錄>

將來源目錄底下以下項目複製到目的目錄 (不存在則跳過):
$(printf '  - %s\n' "${ITEMS_TO_COPY[@]}")

選項:
  -h, --help    顯示此說明
EOF
}

# --- 解析參數 ---
if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 2 ]]; then
    log_error "需要兩個參數：來源目錄 與 目的目錄"
    usage
    exit 1
fi

SRC_DIR="$1"
DST_DIR="$2"

# --- 驗證來源目錄 ---
if [[ ! -d "$SRC_DIR" ]]; then
    log_error "來源目錄不存在: $SRC_DIR"
    exit 1
fi

# --- 建立目的目錄 (若不存在) ---
if [[ ! -d "$DST_DIR" ]]; then
    log_info "目的目錄不存在，建立: $DST_DIR"
    mkdir -p "$DST_DIR"
fi

# 取得絕對路徑以便訊息更清楚
SRC_ABS="$(cd "$SRC_DIR" && pwd)"
DST_ABS="$(cd "$DST_DIR" && pwd)"

log_info "來源: $SRC_ABS"
log_info "目的: $DST_ABS"
echo

copied=0
skipped=0
failed=0

for item in "${ITEMS_TO_COPY[@]}"; do
    src_path="$SRC_ABS/$item"
    dst_path="$DST_ABS/$item"

    if [[ -d "$src_path" ]]; then
        # 複製資料夾
        log_info "複製資料夾: $item ..."
        mkdir -p "$dst_path"
        if cp -a "$src_path/." "$dst_path/"; then
            log_ok "已複製: $item  ->  $dst_path"
            ((copied+=1))
        else
            log_error "複製失敗: $item"
            ((failed+=1))
        fi
    elif [[ -f "$src_path" ]]; then
        # 複製檔案
        log_info "複製檔案: $item ..."
        if cp -a "$src_path" "$dst_path"; then
            log_ok "已複製: $item  ->  $dst_path"
            ((copied+=1))
        else
            log_error "複製失敗: $item"
            ((failed+=1))
        fi
    else
        log_warn "來源無此項目，跳過: $item"
        ((skipped+=1))
    fi
done

echo
log_info "完成 — 已複製: ${copied}，跳過: ${skipped}，失敗: ${failed}"

# 若有失敗則以非零狀態退出
[[ $failed -eq 0 ]]
