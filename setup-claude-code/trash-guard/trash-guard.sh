#!/usr/bin/env bash
# ==============================================================================
# TRASH-GUARD.SH — HỆ THỐNG BẢO VỆ CHẶN XÓA CỨNG (BASH / GIT BASH)
# ==============================================================================
# Quy tắc tiên quyết: Tuyệt đối không xóa cứng/vĩnh viễn file hoặc thư mục.
# Bắt buộc chuyển vào thùng rác (Windows Recycle Bin) qua lệnh 'trash'.

_block_hard_delete() {
    cat << 'EOF' >&2
[LỖI NGHIÊM TRỌNG] Thao tác xóa cứng bị chặn!
QUY TẮC TIÊN QUYẾT: TUYỆT ĐỐI KHÔNG ĐƯỢC xoá cứng/xoá vĩnh viễn file hoặc thư mục.
BẮT BUỘC phải dùng lệnh di chuyển vào thùng rác (Trash / Recycle Bin).
Vui lòng dùng: trash <đường_dẫn>
EOF
    return 1
}

# Override functions
rm() { _block_hard_delete "$@"; return 1; }
unlink() { _block_hard_delete "$@"; return 1; }
shred() { _block_hard_delete "$@"; return 1; }
del() { _block_hard_delete "$@"; return 1; }
erase() { _block_hard_delete "$@"; return 1; }
rmdir() { _block_hard_delete "$@"; return 1; }
rd() { _block_hard_delete "$@"; return 1; }

# Export functions for subshells
export -f _block_hard_delete 2>/dev/null || true
export -f rm 2>/dev/null || true
export -f unlink 2>/dev/null || true
export -f shred 2>/dev/null || true
export -f del 2>/dev/null || true
export -f erase 2>/dev/null || true
export -f rmdir 2>/dev/null || true
export -f rd 2>/dev/null || true

# Aliases for interactive shells
shopt -s expand_aliases 2>/dev/null || true
alias rm='_block_hard_delete'
alias unlink='_block_hard_delete'
alias shred='_block_hard_delete'
alias del='_block_hard_delete'
alias erase='_block_hard_delete'
alias rmdir='_block_hard_delete'
alias rd='_block_hard_delete'

trash() {
    if [ $# -eq 0 ]; then
        echo "Sử dụng: trash <đường_dẫn_1> [đường_dẫn_2 ...]" >&2
        return 1
    fi

    local win_args=()
    for item in "$@"; do
        case "$item" in
            -r|-rf|-fr|-f|-R|-Rf|-fR|--recursive|--force)
                continue
                ;;
        esac

        if [ ! -e "$item" ] && [ ! -L "$item" ]; then
            echo "[Trash] Lỗi: Không tìm thấy file hoặc thư mục: $item" >&2
            continue
        fi

        if command -v cygpath >/dev/null 2>&1; then
            win_args+=("$(cygpath -w -a "$item")")
        else
            win_args+=("$item")
        fi
    done

    if [ ${#win_args[@]} -eq 0 ]; then
        return 0
    fi
    local cli_script=""
    if [ -n "$USERPROFILE" ]; then
        cli_script="$USERPROFILE\\.trash-guard\\trash-cli.ps1"
    elif command -v cygpath >/dev/null 2>&1; then
        cli_script="$(cygpath -w "$HOME/.trash-guard/trash-cli.ps1")"
    else
        cli_script="$HOME/.trash-guard/trash-cli.ps1"
    fi

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$cli_script" "${win_args[@]}"
}
export -f trash 2>/dev/null || true
alias recycle='trash'
