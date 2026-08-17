#!/usr/bin/env bash
# git-chmod+x.sh - 批量给仓库中所有文本脚本设置可执行位 (100644 -> 100755)
#
# 用途:
#   Windows 下 git 不支持 Unix 文件权限, 新增的 .sh/.py/.pl/.service 等脚本
#   提交后 mode 会变成 100644, Linux 端 pull 下来无法直接执行. 本脚本通过
#   `git update-index --chmod=+x` 把可执行位写入 git index, 让权限随仓库走,
#   Linux 端 pull 后自然就是 755.
#
# 用法:
#   bash git-chmod+x.sh            # 给所有匹配的已跟踪文件加可执行位
#   bash git-chmod+x.sh --dry-run  # 只打印将要修改的文件, 不实际修改
#   bash git-chmod+x.sh --ext sh   # 只处理 .sh 文件 (默认处理 sh/py/pl/service)
#
# 注意:
#   - 仅对已被 git 跟踪的文件生效; 新文件需先 `git add` 再运行本脚本.
#   - 修改后需 `git commit` 才会生效; Linux 端 pull 后即得到 755.
#   - Windows 端工作区文件本身不会变成可执行 (NTFS 无此位), 这是正常的,
#     真正的权限信息保存在 git index 中, Linux 端 checkout/pull 时落地.

set -euo pipefail

# 默认处理的扩展名
DEFAULT_EXTS=("sh" "py" "pl" "service")

# 解析参数
DRY_RUN=0
EXTS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=1
            shift
            ;;
        --ext)
            shift
            [[ $# -gt 0 ]] || { echo "错误: --ext 后需指定扩展名" >&2; exit 1; }
            EXTS+=("$1")
            shift
            ;;
        --ext=*)
            EXTS+=("${1#--ext=}")
            shift
            ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "未知参数: $1 (使用 -h 查看帮助)" >&2
            exit 1
            ;;
    esac
done

# 未指定 --ext 则用默认列表
[[ ${#EXTS[@]} -eq 0 ]] && EXTS=("${DEFAULT_EXTS[@]}")

# 切换到仓库根目录
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "错误: 当前不在 git 仓库中" >&2
    exit 1
}
cd "$REPO_ROOT"

# 构造 git ls-files 的 pathspec: *.sh *.py *.pl *.service
PATHSPEC=()
for ext in "${EXTS[@]}"; do
    PATHSPEC+=("*.$ext")
done

# 收集所有已跟踪的匹配文件
mapfile -t FILES < <(git ls-files -- "${PATHSPEC[@]}")

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "未找到匹配的已跟踪文件 (扩展名: ${EXTS[*]})"
    exit 0
fi

CHANGED=0
UNCHANGED=0
for f in "${FILES[@]}"; do
    # 读取 index 中的 mode 和 blob hash (格式: <mode> <hash> <stage>\t<path>)
    line=$(git ls-files --stage -- "$f")
    mode=$(echo "$line" | awk '{print $1}')
    hash=$(echo "$line" | awk '{print $2}')
    if [[ "$mode" == "100755" ]]; then
        UNCHANGED=$((UNCHANGED + 1))
        continue
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] 将设置可执行位: $f  ($mode -> 100755)"
    else
        # 用 --cacheinfo 只改 mode, 保留原 blob hash.
        # 注意: 不能用 `git update-index --chmod=+x <file>`, 因为它在
        # core.autocrlf=true 的 Windows 端会直接读取工作区 CRLF 内容写入
        # 新 blob, 导致仓库里 LF 文件被污染成 CRLF. --cacheinfo 方式绕过
        # 工作区, 直接在 index 中用原 hash + 新 mode 替换条目.
        git update-index --cacheinfo 100755,"$hash","$f"
        echo "[OK]      已设置可执行位: $f  ($mode -> 100755)"
    fi
    CHANGED=$((CHANGED + 1))
done

echo "----------------------------------------"
echo "匹配文件总数: ${#FILES[@]}"
echo "本次将修改:   $CHANGED"
echo "已是 755:     $UNCHANGED"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry-run 模式, 未实际修改)"
else
    echo ""
    echo "下一步: git add -u && git commit -m 'chore: 给所有脚本设置可执行位以兼容 Linux 端'"
fi
