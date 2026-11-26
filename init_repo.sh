#!/bin/bash

# 第五纪双臂轮式人形机器人W1 ROS2部署工作空间初始化脚本
# 功能：勾选嵌套子模块 + 逐模块 source/deb 选择初始化，并支持源码↔deb 切换

# 不设置 set -e，允许某些命令失败后继续执行
set -u  # 遇到未定义变量时退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
MODE_STATE_FILE="$REPO_DIR/.core_module_mode"

# 模块安装方式：1=deb，0=source
USE_DEB_OCS2=1
USE_DEB_ARMS=0
USE_DEB_COMMON=0
INIT_MODE="public"
FLOW="init"  # init | deb_only | deb_uninstall | switch | rosdep
NONINTERACTIVE=0
FORCE_HTTPS=0
ASSUME_YES=0
UI_LANG="zh"  # zh | en
CLI_FLOW=""
CLI_VIS=""
CLI_OCS2=""
CLI_ARMS=""
CLI_COMMON=""
CLI_ONLY=""
CLI_LANG=""
REWRITTEN_GITMODULES_REPOS=()

# 交互文案（zh / en）；日志类 print_* 仍以中文为主
msg() {
    case "$UI_LANG:$1" in
        zh:menu_title) echo "请选择操作：" ;;
        en:menu_title) echo "Select an action:" ;;
        zh:menu_1) echo "  1) 初始化工作空间（勾选嵌套子模块 + 逐模块 source/deb）" ;;
        en:menu_1) echo "  1) Initialize workspace (pick nested submodules + per-module source/deb)" ;;
        zh:menu_1_hint) echo "     默认推荐: ocs2=deb，arms=source，common=source" ;;
        en:menu_1_hint) echo "     Recommended default: ocs2=deb, arms=source, common=source" ;;
        zh:menu_2) echo "  2) 切换模块安装方式（源码 ↔ deb）" ;;
        en:menu_2) echo "  2) Switch module install mode (source ↔ deb)" ;;
        zh:menu_3) echo "  3) 仅安装/更新核心 deb 包（跳过 Git 子模块拉取）" ;;
        en:menu_3) echo "  3) Install/update core debs only (skip Git submodule fetch)" ;;
        zh:menu_4) echo "  4) 卸载核心 deb 包" ;;
        en:menu_4) echo "  4) Uninstall core debs" ;;
        zh:menu_5) echo "  5) 仅运行 rosdep 安装依赖（rosdep install --from-paths src --ignore-src -r -y）" ;;
        en:menu_5) echo "  5) Run rosdep only (rosdep install --from-paths src --ignore-src -r -y)" ;;
        zh:menu_6) echo "  6) 切换语言 / Switch language（当前: 中文）" ;;
        en:menu_6) echo "  6) Switch language / 切换语言 (current: English)" ;;
        zh:menu_prompt) echo "请输入选项 [1-6]（默认: 1）: " ;;
        en:menu_prompt) echo "Enter choice [1-6] (default: 1): " ;;
        zh:lang_switched) echo "已切换界面语言为中文。" ;;
        en:lang_switched) echo "UI language switched to English." ;;
        zh:pick_title) echo "请勾选要初始化的嵌套子模块" ;;
        en:pick_title) echo "Select nested submodules to initialize" ;;
        zh:pick_help) echo "  ↑/↓ 移动  空格勾选  a全选  n默认(无hw/plane_seg)  Enter确认  q取消" ;;
        en:pick_help) echo "  ↑/↓ move  Space toggle  a all  n default(no hw/plane_seg)  Enter ok  q quit" ;;
        zh:pick_cancelled) echo "已取消。" ;;
        en:pick_cancelled) echo "Cancelled." ;;
        zh:pick_notty_title) echo "请勾选要初始化的嵌套子模块（非 TTY）" ;;
        en:pick_notty_title) echo "Select nested submodules (non-TTY)" ;;
        zh:pick_notty_help) echo "  回车=默认(public 无 hardware)    a=全选    序号=在默认之外额外勾选" ;;
        en:pick_notty_help) echo "  Enter=default(public, no hardware)    a=all    numbers=add to default" ;;
        zh:pick_notty_prompt) echo "输入序号（空格分隔）: " ;;
        en:pick_notty_prompt) echo "Enter numbers (space-separated): " ;;
        zh:pick_summary) echo "将初始化以下嵌套子模块（${INIT_MODE}）：" ;;
        en:pick_summary) echo "Will initialize these nested submodules (${INIT_MODE}):" ;;
        zh:core_mode_title) echo "选择核心模块安装方式" ;;
        en:core_mode_title) echo "Select core module install mode" ;;
        zh:core_mode_help) echo "  ↑/↓ 移动  空格切换 deb/source  d/s 指定  Enter确认  q取消" ;;
        en:core_mode_help) echo "  ↑/↓ move  Space toggle deb/source  d/s set  Enter ok  q quit" ;;
        zh:core_mode_hint) echo "  提示: arms=deb 时会自动使用 ocs2=deb、common=deb" ;;
        en:core_mode_hint) echo "  Note: arms=deb forces ocs2=deb and common=deb" ;;
        zh:core_default_prefix) echo "默认" ;;
        en:core_default_prefix) echo "default" ;;
        zh:nested_for_switch) echo "嵌套子模块（仅当有模块改为源码时才会用到）：" ;;
        en:nested_for_switch) echo "Nested submodules (used only when a module switches to source):" ;;
        zh:current_module_state) echo "当前模块状态：" ;;
        en:current_module_state) echo "Current module state:" ;;
        zh:deb_only_prompt_title) echo "选择要安装/更新的包（逗号分隔短名，回车=全部）：" ;;
        en:deb_only_prompt_title) echo "Packages to install/update (comma-separated short names; Enter=all):" ;;
        zh:deb_uninstall_prompt_title) echo "选择要卸载的包（逗号分隔短名，回车=全部）：" ;;
        en:deb_uninstall_prompt_title) echo "Packages to uninstall (comma-separated short names; Enter=all):" ;;
        zh:pkg_list_prompt) echo "包列表: " ;;
        en:pkg_list_prompt) echo "Package list: " ;;
        zh:switch_target_title) echo "为每个模块选择目标（s=source, d=deb, k=保持），回车=保持：" ;;
        en:switch_target_title) echo "Choose target per module (s=source, d=deb, k=keep); Enter=keep:" ;;
        zh:switch_target_hint) echo "  注意：选「保持」或目标与当前一致时，不会对该模块做任何 git/deb 操作。" ;;
        en:switch_target_hint) echo "  Note: keep / unchanged target skips git/deb ops for that module." ;;
        zh:switch_target_prompt_suffix) echo "当前" ;;
        en:switch_target_prompt_suffix) echo "current" ;;
        *) echo "[$1]" ;;
    esac
}

load_ui_lang_from_state() {
    local saved
    if [ -f "$MODE_STATE_FILE" ]; then
        saved="$(grep -E '^UI_LANG=' "$MODE_STATE_FILE" 2>/dev/null | cut -d= -f2- || true)"
        case "$saved" in
            zh|en) UI_LANG="$saved" ;;
        esac
    fi
}

normalize_ui_lang() {
    case "$1" in
        zh|zh-CN|zh_CN|cn|CN|chinese|Chinese) echo "zh" ;;
        en|en-US|en_US|english|English) echo "en" ;;
        *) return 1 ;;
    esac
}

VISIBILITY_CONF="$REPO_DIR/submodules_visibility.conf"
NESTED_PUBLIC_SPECS=()
NESTED_PRIVATE_SPECS=()
SELECTED_NESTED_SPECS=()
CATALOG_PARENT=()
CATALOG_PATH=()
CATALOG_VIS=()
CATALOG_SEL=()
CATALOG_N=0
VISIBILITY_LOADED=0

trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }

load_visibility_conf() {
    if [ ! -f "$VISIBILITY_CONF" ]; then
        print_error "未找到配置文件: $VISIBILITY_CONF"
        exit 1
    fi
    NESTED_PUBLIC_SPECS=()
    NESTED_PRIVATE_SPECS=()
    local line parent_dir relative_path visibility gitmodules_file spec
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [ -z "$line" ] && continue
        IFS='|' read -r parent_dir relative_path visibility <<< "$line"
        parent_dir=$(trim "$parent_dir")
        relative_path=$(trim "$relative_path")
        visibility=$(trim "$visibility")
        gitmodules_file="${parent_dir}/.gitmodules"
        spec="${parent_dir}:${gitmodules_file}:${relative_path}"
        case "$visibility" in
            public)  NESTED_PUBLIC_SPECS+=("$spec") ;;
            private) NESTED_PRIVATE_SPECS+=("$spec") ;;
            *)       print_warn "未知可见性 '$visibility'，跳过: $parent_dir/$relative_path" ;;
        esac
    done < "$VISIBILITY_CONF"
    VISIBILITY_LOADED=1
    print_info "已从 $VISIBILITY_CONF 加载嵌套子模块配置（public: ${#NESTED_PUBLIC_SPECS[@]} 项, private: ${#NESTED_PRIVATE_SPECS[@]} 项）"
}

# 默认不勾选（仍在列表，可用空格 / a 选上）：hardware、plane_segmentation、FiveAges Gen1 等
is_default_unchecked_nested_path() {
    case "$1" in
        hardwares|hardwares/*) return 0 ;;
        submodules/plane_segmentation_ros2) return 0 ;;
        plane_segmentation_ros2) return 0 ;;
        humanoid/FiveAges/Gen1/*|*/FiveAges/Gen1/*) return 0 ;;
        humanoid/FiveAges/Gen1/fiveages_w1_description) return 0 ;;
        *) return 1 ;;
    esac
}

CATALOG_LABEL_SHORT=()

catalog_add() {
    local parent="$1" path="$2" vis="$3"
    local lab="${parent}/${path}"
    CATALOG_PARENT+=("$parent")
    CATALOG_PATH+=("$path")
    CATALOG_VIS+=("$vis")
    CATALOG_LABEL_SHORT+=("${lab#src/}")
    # 默认：public 且非「默认不勾选」路径
    if [ "$vis" = "public" ] && ! is_default_unchecked_nested_path "$path"; then
        CATALOG_SEL+=(1)
    else
        CATALOG_SEL+=(0)
    fi
    CATALOG_N=$((CATALOG_N + 1))
}

catalog_label() {
    echo "${CATALOG_PARENT[$1]}/${CATALOG_PATH[$1]}"
}

catalog_label_short() {
    echo "${CATALOG_LABEL_SHORT[$1]}"
}

term_cols() { tput cols 2>/dev/null || echo 80; }
term_lines() { tput lines 2>/dev/null || echo 24; }

# 纯 ASCII 截断（路径）；无子进程
truncate_ascii() {
    local s="$1" max="$2"
    [ "$max" -lt 8 ] && max=8
    if [ "${#s}" -le "$max" ]; then
        printf '%s' "$s"
    else
        printf '%s...' "${s:0:$((max - 3))}"
    fi
}

# 标题/帮助可能含中文：非 ASCII 按 2 列；无子进程
truncate_to_width() {
    local s="$1" max="$2"
    local i=0 ch o width=0 out=""
    [ "$max" -lt 8 ] && max=8
    if [[ "$s" =~ ^[\ $'\t'-~]*$ ]]; then
        truncate_ascii "$s" "$max"
        return 0
    fi
    while [ "$i" -lt "${#s}" ]; do
        ch="${s:i:1}"
        printf -v o '%d' "'$ch"
        if [ "$o" -ge 0 ] && [ "$o" -lt 128 ]; then
            [ $((width + 1)) -gt "$max" ] && break
            out+="$ch"
            width=$((width + 1))
        else
            [ $((width + 2)) -gt "$max" ] && break
            out+="$ch"
            width=$((width + 2))
        fi
        i=$((i + 1))
    done
    if [ "$i" -lt "${#s}" ]; then
        while [ "$width" -gt $((max - 3)) ] && [ -n "$out" ]; do
            ch="${out: -1}"
            out="${out:0:${#out}-1}"
            printf -v o '%d' "'$ch"
            if [ "$o" -ge 0 ] && [ "$o" -lt 128 ]; then
                width=$((width - 1))
            else
                width=$((width - 2))
            fi
        done
        out+="..."
    fi
    printf '%s' "$out"
}

# arms/ocs2/common 用 deb 时，对应嵌套不必出现在勾选列表
should_omit_nested_from_picker() {
    local parent_dir="$1"
    local relative_path="$2"
    case "$parent_dir" in
        src/arms_ros2_control)
            [ "${USE_DEB_ARMS:-0}" -eq 1 ] && return 0
            ;;
        src/ocs2_ros2)
            [ "${USE_DEB_OCS2:-0}" -eq 1 ] && return 0
            ;;
        src/robot-descriptions)
            if [ "$relative_path" = "common" ] && [ "${USE_DEB_COMMON:-0}" -eq 1 ]; then
                return 0
            fi
            ;;
    esac
    return 1
}

build_nested_catalog() {
    CATALOG_PARENT=()
    CATALOG_PATH=()
    CATALOG_VIS=()
    CATALOG_SEL=()
    CATALOG_LABEL_SHORT=()
    CATALOG_N=0
    local spec parent_dir rest relative_path vis s
    for spec in "${NESTED_PUBLIC_SPECS[@]+"${NESTED_PUBLIC_SPECS[@]}"}" "${NESTED_PRIVATE_SPECS[@]+"${NESTED_PRIVATE_SPECS[@]}"}"; do
        [ -z "${spec:-}" ] && continue
        parent_dir="${spec%%:*}"
        rest="${spec#*:}"
        relative_path="${rest#*:}"
        if should_omit_nested_from_picker "$parent_dir" "$relative_path"; then
            continue
        fi
        vis="private"
        for s in "${NESTED_PUBLIC_SPECS[@]+"${NESTED_PUBLIC_SPECS[@]}"}"; do
            [ "$s" = "$spec" ] && vis="public" && break
        done
        catalog_add "$parent_dir" "$relative_path" "$vis"
    done
}

catalog_reset_public() {
    # 与默认勾选一致：public，不含 hardwares/、plane_segmentation、FiveAges Gen1
    local i
    for ((i = 0; i < CATALOG_N; i++)); do
        if [ "${CATALOG_VIS[$i]}" = "public" ] && ! is_default_unchecked_nested_path "${CATALOG_PATH[$i]}"; then
            CATALOG_SEL[$i]=1
        else
            CATALOG_SEL[$i]=0
        fi
    done
}

catalog_select_all() {
    local i
    for ((i = 0; i < CATALOG_N; i++)); do
        CATALOG_SEL[$i]=1
    done
}

apply_catalog_selection() {
    local i parent_dir relative_path gitmodules_file has_private=0
    SELECTED_NESTED_SPECS=()
    for ((i = 0; i < CATALOG_N; i++)); do
        [ "${CATALOG_SEL[$i]}" = "1" ] || continue
        parent_dir="${CATALOG_PARENT[$i]}"
        relative_path="${CATALOG_PATH[$i]}"
        gitmodules_file="${parent_dir}/.gitmodules"
        SELECTED_NESTED_SPECS+=("${parent_dir}:${gitmodules_file}:${relative_path}")
        if [ "${CATALOG_VIS[$i]}" = "private" ]; then
            has_private=1
        fi
    done
    if [ "$has_private" -eq 1 ]; then
        INIT_MODE="private"
    else
        INIT_MODE="public"
    fi
}

# ════════════════════════════════════════════════════════════════
# 全屏列表 UI（核心模块 / 嵌套子模块共用）
# - 行差量刷新：不每次 \033[2J，避免整屏闪
# - DEC 2026 同步输出：多行更新原子提交（支持的终端）
# ════════════════════════════════════════════════════════════════

enter_fullscreen() {
    local enable_mouse="${1:-1}"
    if tput smcup 2>/dev/null; then
        :
    else
        printf '\033[?1049h'
    fi
    printf '\033[?25l'
    if [ "$enable_mouse" = "1" ]; then
        printf '\033[?1000h\033[?1006h'
    fi
}

leave_fullscreen() {
    printf '\033[?1006l\033[?1000l'
    printf '\033[?25h'
    if tput rmcup 2>/dev/null; then
        :
    else
        printf '\033[?1049l'
    fi
}

# 排空多余 CSI（鼠标滚轮等），超时尽量短
drain_csi() {
    local ch
    while IFS= read -rsn1 -t 0.001 ch; do
        case "$ch" in
            ''|[A-Za-z~Mm]) break ;;
        esac
    done
}

# 帧缓冲：FS_OLD_LINE[row]=上次内容；FLUSH 只写变化行
FS_LINES=24
FS_COLS=80
FS_OLD_LINE=()
FS_NEW_LINE=()
FS_KEY=""
WINCH_FLAG=0

fs_frame_invalidate() {
    FS_OLD_LINE=()
}

fs_frame_begin() {
    FS_COLS=$(term_cols)
    FS_LINES=$(term_lines)
    [ "$FS_COLS" -lt 20 ] && FS_COLS=20
    [ "$FS_LINES" -lt 4 ] && FS_LINES=4
    PICKER_LINES=$FS_LINES
    FS_NEW_LINE=()
}

fs_frame_put() {
    FS_NEW_LINE[$1]="$2"
}

# 填满 1..FS_LINES，未 put 的行视为空（清残留）
fs_frame_flush() {
    local r text old
    printf '\033[?2026h'
    for ((r = 1; r <= FS_LINES; r++)); do
        text="${FS_NEW_LINE[$r]-}"
        old="${FS_OLD_LINE[$r]-}"
        if [ "$text" != "$old" ]; then
            printf '\033[%d;1H\033[2K%s' "$r" "$text"
            FS_OLD_LINE[$r]="$text"
        fi
    done
    printf '\033[?2026l'
}

# 读一键：设置 FS_KEY = UP|DOWN|SPACE|ENTER|QUIT|TIMEOUT|WINCH|CHAR:x|UNKNOWN
# 依赖外部 WINCH_FLAG；mouse=1 时解析滚轮为 UP/DOWN
fs_poll_key() {
    local key="" k2="" k3="" c btn
    if [ "${WINCH_FLAG:-0}" -eq 1 ]; then
        FS_KEY=WINCH
        return 0
    fi
    if ! IFS= read -rsn1 -t 0.2 key; then
        if [ "${WINCH_FLAG:-0}" -eq 1 ]; then
            FS_KEY=WINCH
        else
            FS_KEY=TIMEOUT
        fi
        return 0
    fi
    if [ "$key" = $'\x1b' ]; then
        IFS= read -rsn1 -t 0.001 k2 || k2=""
        if [ -z "$k2" ]; then
            FS_KEY=UNKNOWN
            return 0
        fi
        if [ "$k2" = "[" ]; then
            IFS= read -rsn1 -t 0.001 k3 || k3=""
            case "$k3" in
                A) FS_KEY=UP; return 0 ;;
                B) FS_KEY=DOWN; return 0 ;;
                \<)
                    btn=""
                    while IFS= read -rsn1 -t 0.001 c; do
                        case "$c" in
                            [0-9]) btn+="$c" ;;
                            \;|[Mm]) break ;;
                            *) break ;;
                        esac
                    done
                    drain_csi
                    if [ "$btn" = "64" ]; then
                        FS_KEY=UP
                    elif [ "$btn" = "65" ]; then
                        FS_KEY=DOWN
                    else
                        FS_KEY=UNKNOWN
                    fi
                    return 0
                    ;;
                M)
                    IFS= read -rsn1 -t 0.001 _ || true
                    IFS= read -rsn1 -t 0.001 _ || true
                    IFS= read -rsn1 -t 0.001 _ || true
                    FS_KEY=UNKNOWN
                    return 0
                    ;;
                *)
                    drain_csi
                    FS_KEY=UNKNOWN
                    return 0
                    ;;
            esac
        fi
        FS_KEY=UNKNOWN
        return 0
    elif [ "$key" = " " ]; then
        FS_KEY=SPACE
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
        FS_KEY=QUIT
    elif [ -z "$key" ]; then
        FS_KEY=ENTER
    else
        FS_KEY="CHAR:$key"
    fi
}

# 二级路径分组键：robot-descriptions/manipulator、arms_ros2_control/hardwares …
picker_group_key() {
    local lab="$1" a rest b
    a="${lab%%/*}"
    rest="${lab#*/}"
    if [ "$rest" = "$lab" ]; then
        printf '%s' "$a"
    else
        b="${rest%%/*}"
        printf '%s/%s' "$a" "$b"
    fi
}

# 构建显示行：item:<catalog_idx> 或 sep（组间空行）
build_picker_display() {
    local i prev="" group lab
    PICKER_DISP=()
    PICKER_DISP_N=0
    CATALOG_TO_DISP=()
    for ((i = 0; i < CATALOG_N; i++)); do
        lab="${CATALOG_LABEL_SHORT[$i]}"
        group="$(picker_group_key "$lab")"
        if [ -n "$prev" ] && [ "$group" != "$prev" ]; then
            PICKER_DISP+=("sep")
            PICKER_DISP_N=$((PICKER_DISP_N + 1))
        fi
        CATALOG_TO_DISP[$i]=$PICKER_DISP_N
        PICKER_DISP+=("item:$i")
        PICKER_DISP_N=$((PICKER_DISP_N + 1))
        prev="$group"
    done
}

# 列表行文本（路径为 ASCII，用 truncate_ascii）
picker_item_line() {
    local i="$1" cur="$2" cols="$3"
    local mark vis_tag prefix
    if [ "${CATALOG_SEL[$i]}" = "1" ]; then
        mark="[x]"
    else
        mark="[ ]"
    fi
    vis_tag="${CATALOG_VIS[$i]}"
    if [ "$i" -eq "$cur" ]; then
        prefix=" > $mark [$vis_tag]  "
    else
        prefix="   $mark [$vis_tag]  "
    fi
    truncate_ascii "${prefix}${CATALOG_LABEL_SHORT[$i]}" "$cols"
}

picker_footer_line() {
    local cur="$1" win_start="$2" visible="$3" cols="$4" disp_n="$5"
    local end=$((win_start + visible)) line
    [ "$end" -gt "$disp_n" ] && end=$disp_n
    if [ "$UI_LANG" = "en" ]; then
        line="  ($((cur + 1))/$CATALOG_N)  up/down scroll"
    else
        line="  ($((cur + 1))/$CATALOG_N)  上下滚动"
    fi
    if [ "$win_start" -gt 0 ] || [ "$end" -lt "$disp_n" ]; then
        line="$line  ..."
    fi
    truncate_ascii "$line" "$cols"
}

# ── 核心模块：deb|source 全屏选择 ───────────────────────────────
pick_core_module_modes() {
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        msg core_mode_title
        prompt_sd "  ocs2_ros2              $(msg core_default_prefix) $(mode_label "$USE_DEB_OCS2")" \
            "$( [ "$USE_DEB_OCS2" -eq 1 ] && echo d || echo s )" USE_DEB_OCS2
        prompt_sd "  arms_ros2_control      $(msg core_default_prefix) $(mode_label "$USE_DEB_ARMS")" \
            "$( [ "$USE_DEB_ARMS" -eq 1 ] && echo d || echo s )" USE_DEB_ARMS
        prompt_sd "  robot-descriptions/common $(msg core_default_prefix) $(mode_label "$USE_DEB_COMMON")" \
            "$( [ "$USE_DEB_COMMON" -eq 1 ] && echo d || echo s )" USE_DEB_COMMON
        return 0
    fi
    pick_core_modes_tty
}

pick_core_modes_tty() {
    local idx=0
    local names=( "ocs2_ros2" "arms_ros2_control" "robot-descriptions/common" )
    local modes=( "$USE_DEB_OCS2" "$USE_DEB_ARMS" "$USE_DEB_COMMON" )
    local n=3
    local old_stty picker_active=0
    local title_line help_line hint_line
    local list_top=5
    old_stty=$(stty -g)
    WINCH_FLAG=0
    fs_frame_invalidate

    leave_core_picker() {
        trap - WINCH
        if [ "$picker_active" -eq 1 ]; then
            leave_fullscreen
            picker_active=0
        fi
        stty "$old_stty" 2>/dev/null || true
    }
    on_core_winch() { WINCH_FLAG=1; }
    trap leave_core_picker EXIT INT TERM
    trap on_core_winch WINCH

    apply_arms_deb_constraint() {
        if [ "${modes[1]}" -eq 1 ]; then
            modes[0]=1
            modes[2]=1
        fi
    }

    core_row_text() {
        local i="$1" cur="$2" cols="$3"
        local mode_s prefix
        if [ "${modes[$i]}" -eq 1 ]; then
            mode_s="deb   "
        else
            mode_s="source"
        fi
        if [ "$i" -eq "$cur" ]; then
            prefix=" > "
        else
            prefix="   "
        fi
        truncate_ascii "${prefix}[${mode_s}]  ${names[$i]}" "$cols"
    }

    # 整屏逻辑内容写入帧缓冲后差量 flush（无 2J）
    redraw_core() {
        local i r
        fs_frame_begin
        if [ "$FS_LINES" -lt 8 ]; then
            list_top=3
            help_line="$(truncate_to_width "$(msg core_mode_help)" "$FS_COLS")"
            fs_frame_put 1 "$help_line"
            fs_frame_put 2 ""
        else
            list_top=5
            title_line="$(truncate_to_width "$(msg core_mode_title)" "$FS_COLS")"
            help_line="$(truncate_to_width "$(msg core_mode_help)" "$FS_COLS")"
            hint_line="$(truncate_to_width "$(msg core_mode_hint)" "$FS_COLS")"
            fs_frame_put 1 "$title_line"
            fs_frame_put 2 "$help_line"
            fs_frame_put 3 "$hint_line"
            fs_frame_put 4 ""
        fi
        for ((i = 0; i < n; i++)); do
            fs_frame_put $((list_top + i)) "$(core_row_text "$i" "$idx" "$FS_COLS")"
        done
        # 其余行由 flush 写成空，清掉缩放残留
        fs_frame_flush
        WINCH_FLAG=0
    }

    stty -echo -icanon
    enter_fullscreen 0
    picker_active=1
    apply_arms_deb_constraint
    redraw_core

    while true; do
        fs_poll_key
        case "$FS_KEY" in
            WINCH|TIMEOUT)
                [ "$FS_KEY" = "WINCH" ] && redraw_core
                continue
                ;;
            UP)
                idx=$(( (idx - 1 + n) % n ))
                redraw_core
                ;;
            DOWN)
                idx=$(( (idx + 1) % n ))
                redraw_core
                ;;
            SPACE)
                if [ "${modes[$idx]}" -eq 1 ]; then
                    modes[$idx]=0
                else
                    modes[$idx]=1
                fi
                apply_arms_deb_constraint
                redraw_core
                ;;
            CHAR:d|CHAR:D)
                modes[$idx]=1
                apply_arms_deb_constraint
                redraw_core
                ;;
            CHAR:s|CHAR:S)
                modes[$idx]=0
                apply_arms_deb_constraint
                redraw_core
                ;;
            QUIT)
                leave_core_picker
                trap - EXIT INT TERM
                msg pick_cancelled
                exit 0
                ;;
            ENTER)
                USE_DEB_OCS2="${modes[0]}"
                USE_DEB_ARMS="${modes[1]}"
                USE_DEB_COMMON="${modes[2]}"
                apply_arms_deb_constraint
                USE_DEB_OCS2="${modes[0]}"
                USE_DEB_ARMS="${modes[1]}"
                USE_DEB_COMMON="${modes[2]}"
                leave_core_picker
                trap - EXIT INT TERM
                print_info "核心模块: ocs2=$(mode_label "$USE_DEB_OCS2"), arms=$(mode_label "$USE_DEB_ARMS"), common=$(mode_label "$USE_DEB_COMMON")"
                break
                ;;
        esac
    done
}

# ── 嵌套子模块全屏勾选 ─────────────────────────────────────────
pick_submodules_tty() {
    local idx=0
    local header=3 footer=1 visible win_start=0
    local old_stty picker_active=0
    local title_line help_line
    local list_top=4
    local disp_idx=0
    local prev_cols=0 prev_lines=0
    PICKER_DISP=()
    PICKER_DISP_N=0
    CATALOG_TO_DISP=()
    old_stty=$(stty -g)
    WINCH_FLAG=0
    fs_frame_invalidate

    leave_picker_screen() {
        trap - WINCH
        if [ "$picker_active" -eq 1 ]; then
            leave_fullscreen
            picker_active=0
        fi
        stty "$old_stty" 2>/dev/null || true
    }
    on_winch() { WINCH_FLAG=1; }
    trap leave_picker_screen EXIT INT TERM
    trap on_winch WINCH

    build_picker_display
    disp_idx=${CATALOG_TO_DISP[0]:-0}
    idx=0

    stty -echo -icanon
    enter_fullscreen 1
    picker_active=1

    sync_window() {
        fs_frame_begin
        if [ "$FS_LINES" -lt 8 ]; then
            header=2
            list_top=3
            footer=1
        else
            header=3
            list_top=4
            footer=1
        fi
        visible=$((FS_LINES - header - footer))
        [ "$visible" -lt 1 ] && visible=1
        [ "$visible" -gt "$PICKER_DISP_N" ] && visible=$PICKER_DISP_N

        disp_idx=${CATALOG_TO_DISP[$idx]:-0}
        if [ "$disp_idx" -lt "$win_start" ]; then
            win_start=$disp_idx
        elif [ "$disp_idx" -ge $((win_start + visible)) ]; then
            win_start=$((disp_idx - visible + 1))
        fi
        [ "$win_start" -lt 0 ] && win_start=0
        local max_start=$((PICKER_DISP_N - visible))
        [ "$max_start" -lt 0 ] && max_start=0
        [ "$win_start" -gt "$max_start" ] && win_start=$max_start

        if [ "$FS_COLS" -ne "$prev_cols" ] || [ "$FS_LINES" -ne "$prev_lines" ]; then
            fs_frame_invalidate
        fi
    }

    paint_disp_into_frame() {
        local d="$1" screen_row="$2" cur="$3"
        local ent cat_i
        ent="${PICKER_DISP[$d]-sep}"
        case "$ent" in
            item:*)
                cat_i="${ent#item:}"
                fs_frame_put "$screen_row" "$(picker_item_line "$cat_i" "$cur" "$FS_COLS")"
                ;;
            *)
                fs_frame_put "$screen_row" ""
                ;;
        esac
    }

    redraw_list() {
        local d end r footer_row
        sync_window
        if [ "$header" -ge 3 ]; then
            title_line="$(truncate_to_width "$(msg pick_title)" "$FS_COLS")"
            help_line="$(truncate_to_width "$(msg pick_help)" "$FS_COLS")"
            fs_frame_put 1 "$title_line"
            fs_frame_put 2 "$help_line"
            fs_frame_put 3 ""
        else
            help_line="$(truncate_to_width "$(msg pick_help)" "$FS_COLS")"
            fs_frame_put 1 "$help_line"
            fs_frame_put 2 ""
        fi
        end=$((win_start + visible))
        [ "$end" -gt "$PICKER_DISP_N" ] && end=$PICKER_DISP_N
        r=$list_top
        for ((d = win_start; d < end; d++)); do
            paint_disp_into_frame "$d" "$r" "$idx"
            r=$((r + 1))
        done
        footer_row=$((list_top + visible))
        [ "$footer_row" -gt "$FS_LINES" ] && footer_row=$FS_LINES
        fs_frame_put "$footer_row" "$(picker_footer_line "$idx" "$win_start" "$visible" "$FS_COLS" "$PICKER_DISP_N")"
        fs_frame_flush
        prev_cols=$FS_COLS
        prev_lines=$FS_LINES
        WINCH_FLAG=0
    }

    move_sel() {
        local dir="$1"
        local next=$((idx + dir))
        if [ "$next" -lt 0 ]; then
            next=$((CATALOG_N - 1))
        elif [ "$next" -ge "$CATALOG_N" ]; then
            next=0
        fi
        idx=$next
    }

    redraw_list
    while true; do
        fs_poll_key
        case "$FS_KEY" in
            WINCH)
                redraw_list
                ;;
            TIMEOUT)
                continue
                ;;
            UP)
                move_sel -1
                redraw_list
                ;;
            DOWN)
                move_sel 1
                redraw_list
                ;;
            SPACE)
                CATALOG_SEL[$idx]=$((1 - CATALOG_SEL[$idx]))
                redraw_list
                ;;
            CHAR:a|CHAR:A)
                catalog_select_all
                redraw_list
                ;;
            CHAR:n|CHAR:N)
                catalog_reset_public
                redraw_list
                ;;
            QUIT)
                leave_picker_screen
                trap - EXIT INT TERM
                msg pick_cancelled
                exit 0
                ;;
            ENTER)
                leave_picker_screen
                trap - EXIT INT TERM
                break
                ;;
        esac
    done
}

pick_submodules_notty() {
    local i mark vis_tag input n prev="" group
    msg pick_notty_title
    msg pick_notty_help
    echo ""
    for ((i = 0; i < CATALOG_N; i++)); do
        group="$(picker_group_key "${CATALOG_LABEL_SHORT[$i]}")"
        if [ -n "$prev" ] && [ "$group" != "$prev" ]; then
            echo ""
        fi
        prev="$group"
        if [ "${CATALOG_SEL[$i]}" = "1" ]; then
            mark="[x]"
        else
            mark="[ ]"
        fi
        vis_tag="${CATALOG_VIS[$i]}"
        printf "  %2d) %s [%s]  %s\n" "$((i + 1))" "$mark" "$vis_tag" "${CATALOG_LABEL_SHORT[$i]}"
    done
    echo ""
    read -rp "$(msg pick_notty_prompt)" input
    case "$input" in
        a|A) catalog_select_all ;;
        "") ;;
        *)
            catalog_reset_public
            for n in $input; do
                if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "$CATALOG_N" ]; then
                    CATALOG_SEL[$((n - 1))]=1
                else
                    print_warn "忽略无效序号: $n"
                fi
            done
            ;;
    esac
}

pick_nested_submodules() {
    if [ "$CATALOG_N" -eq 0 ]; then
        SELECTED_NESTED_SPECS=()
        if [ "${USE_DEB_ARMS:-0}" -eq 1 ] && [ "${USE_DEB_OCS2:-0}" -eq 1 ]; then
            print_info "arms/ocs2 均为 deb，且无其余可选嵌套，跳过勾选"
        else
            print_info "当前 source/deb 选择下无需勾选嵌套子模块"
        fi
        return 0
    fi
    if [ -t 0 ] && [ -t 1 ]; then
        pick_submodules_tty
    else
        pick_submodules_notty
    fi
    apply_catalog_selection
    local i
    print_info "$(msg pick_summary)"
    for ((i = 0; i < CATALOG_N; i++)); do
        if [ "${CATALOG_SEL[$i]}" = "1" ]; then
            print_info "  - $(catalog_label "$i") (${CATALOG_VIS[$i]})"
        fi
    done
}

apply_visibility_preset() {
    local mode="$1"
    build_nested_catalog
    case "$mode" in
        public) catalog_reset_public ;;  # public，默认不含 hardwares/、plane_segmentation
        private) catalog_select_all ;;   # 全部（含 private + 默认可选项）
        *)
            print_error "无效可见性预设: $mode（可用: public, private）"
            exit 1
            ;;
    esac
    apply_catalog_selection
    print_info "嵌套子模块预设: $mode（已选 ${#SELECTED_NESTED_SPECS[@]} 项；默认不含 hardwares/、plane_segmentation、FiveAges Gen1）"
}

ensure_nested_selection() {
    # 交互：勾选；非交互 / 已传 --public|--private：按预设
    if [ "$VISIBILITY_LOADED" -eq 0 ]; then
        load_visibility_conf
    fi
    build_nested_catalog
    if [ -n "$CLI_VIS" ] || [ "$NONINTERACTIVE" -eq 1 ]; then
        apply_visibility_preset "${CLI_VIS:-$INIT_MODE}"
    else
        pick_nested_submodules
    fi
}

run_rosdep_install() {
    print_info "运行: rosdep install --from-paths src --ignore-src -r -y"
    if ! command -v rosdep >/dev/null 2>&1; then
        print_error "未找到 rosdep，请先安装 ROS 环境后重试"
        print_info "  sudo apt install python3-rosdep"
        print_info "  sudo rosdep init && rosdep update"
        return 1
    fi
    if [ ! -d "$REPO_DIR/src" ]; then
        print_error "未找到 src 目录: $REPO_DIR/src"
        return 1
    fi
    rosdep install --from-paths src --ignore-src -r -y \
        || print_warn "rosdep 安装部分依赖失败，可稍后重试或检查 package.xml"
}

run_install_core_debs() {
    local only_list="${1:-}"
    print_info "安装核心 deb 包（顺序: ocs2 → common → arms_ros2_control）..."
    local install_script="$REPO_DIR/scripts/install_core_debs.sh"
    if [ ! -x "$install_script" ]; then
        chmod +x "$install_script" 2>/dev/null || true
    fi
    if [ ! -f "$install_script" ]; then
        print_error "未找到安装脚本: $install_script"
        return 1
    fi
    if [ -n "$only_list" ]; then
        bash "$install_script" --only "$only_list"
    else
        bash "$install_script"
    fi
}

run_uninstall_core_debs() {
    local only_list="${1:-}"
    print_info "卸载核心 deb 包（顺序: arms_ros2_control → common → ocs2）..."
    local uninstall_script="$REPO_DIR/scripts/uninstall_core_debs.sh"
    if [ ! -x "$uninstall_script" ]; then
        chmod +x "$uninstall_script" 2>/dev/null || true
    fi
    if [ ! -f "$uninstall_script" ]; then
        print_error "未找到卸载脚本: $uninstall_script"
        return 1
    fi
    if [ -n "$only_list" ]; then
        bash "$uninstall_script" --only "$only_list"
    else
        bash "$uninstall_script"
    fi
}

save_module_mode_state() {
    cat > "$MODE_STATE_FILE" <<EOF
# 上次 init_repo.sh 选择的模块安装方式（deb=1 / source=0）与界面语言
INIT_MODE=$INIT_MODE
USE_DEB_OCS2=$USE_DEB_OCS2
USE_DEB_ARMS=$USE_DEB_ARMS
USE_DEB_COMMON=$USE_DEB_COMMON
UI_LANG=$UI_LANG
EOF
}

is_pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

path_has_submodule_content() {
    local path="$1"
    [ -d "$REPO_DIR/$path" ] || return 1
    [ -e "$REPO_DIR/$path/.git" ] && return 0
    [ -n "$(ls -A "$REPO_DIR/$path" 2>/dev/null)" ]
}

path_is_git_checkout() {
    local path="$1"
    [ -e "$REPO_DIR/$path/.git" ] || return 1
    (cd "$REPO_DIR/$path" && git rev-parse --git-dir >/dev/null 2>&1)
}

detect_module_state() {
    # 输出: deb | source | mixed | none
    local path="$1"
    local deb_pkg="$2"
    local has_deb=0 has_src=0
    is_pkg_installed "$deb_pkg" && has_deb=1
    path_is_git_checkout "$path" && has_src=1
    if [ "$has_deb" -eq 1 ] && [ "$has_src" -eq 1 ]; then
        echo "mixed"
    elif [ "$has_deb" -eq 1 ]; then
        echo "deb"
    elif [ "$has_src" -eq 1 ]; then
        echo "source"
    else
        echo "none"
    fi
}

module_short_to_path() {
    case "$1" in
        ocs2) echo "src/ocs2_ros2" ;;
        arms) echo "src/arms_ros2_control" ;;
        common) echo "src/robot-descriptions/common" ;;
        *) return 1 ;;
    esac
}

module_short_to_deb() {
    case "$1" in
        ocs2) echo "ros-jazzy-ocs2" ;;
        arms) echo "ros-jazzy-arms-ros2-control" ;;
        common) echo "ros-jazzy-robot-descriptions-common" ;;
        *) return 1 ;;
    esac
}

get_use_deb_for_module() {
    case "$1" in
        ocs2) echo "$USE_DEB_OCS2" ;;
        arms) echo "$USE_DEB_ARMS" ;;
        common) echo "$USE_DEB_COMMON" ;;
        *) echo "0" ;;
    esac
}

set_use_deb_for_module() {
    case "$1" in
        ocs2) USE_DEB_OCS2="$2" ;;
        arms) USE_DEB_ARMS="$2" ;;
        common) USE_DEB_COMMON="$2" ;;
    esac
}

selected_deb_only_list() {
    local parts=()
    [ "$USE_DEB_OCS2" -eq 1 ] && parts+=("ocs2")
    [ "$USE_DEB_COMMON" -eq 1 ] && parts+=("common")
    [ "$USE_DEB_ARMS" -eq 1 ] && parts+=("arms")
    if [ ${#parts[@]} -eq 0 ]; then
        echo ""
    else
        local IFS=,
        echo "${parts[*]}"
    fi
}

prompt_sd() {
    # $1=提示 $2=默认 d|s → 设置变量名为 $3 的 1/0
    local prompt="$1"
    local default="$2"
    local __result_var="$3"
    local choice default_hint
    if [ "$default" = "d" ]; then
        default_hint="D/s"
    else
        default_hint="d/S"
    fi
    read -rp "$prompt [$default_hint]: " choice
    choice="${choice:-$default}"
    case "$choice" in
        d|D|deb|DEB) printf -v "$__result_var" '%s' "1" ;;
        s|S|source|SOURCE) printf -v "$__result_var" '%s' "0" ;;
        *)
            if [ "$default" = "d" ]; then
                printf -v "$__result_var" '%s' "1"
            else
                printf -v "$__result_var" '%s' "0"
            fi
            ;;
    esac
}

mode_label() {
    if [ "$1" -eq 1 ]; then
        echo "deb"
    else
        echo "source"
    fi
}

env_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

parse_ds_value() {
    case "$1" in
        d|D|deb|DEB) echo 1 ;;
        s|S|source|SOURCE) echo 0 ;;
        *) return 1 ;;
    esac
}

usage() {
    cat <<EOF
用法: ./init_repo.sh [选项]

无参数时进入交互菜单（适合本机手动初始化）。
容器 / CI 请使用非交互参数，避免脚本等待回车。

非交互初始化（与交互默认值一致: public, ocs2=deb, arms=source, common=source）:
  ./init_repo.sh --public --ocs2=deb --arms=source --common=source

嵌套子模块（交互时可勾选；非交互用预设）:
  --public              仅 public 嵌套，默认不含 hardwares/、plane_segmentation（可再勾选）
  --private             全部嵌套（含 private + 默认可选项，需要仓库访问权限）
  交互界面: ↑/↓ 移动  空格勾选  a 全选  n 恢复默认  Enter 确认

核心模块安装方式:
  --ocs2=deb|source     默认 deb
  --arms=deb|source     默认 source
  --common=deb|source   默认 source

流程:
  --init                初始化工作空间（默认）
  --switch              切换模块安装方式
  --deb-only            仅安装/更新核心 deb
  --deb-uninstall       卸载核心 deb
  --rosdep              仅运行 rosdep
  --only <list>         配合 --deb-only / --deb-uninstall，逗号分隔短名

其他:
  --lang=zh|en          界面语言（交互菜单也可选「切换语言」）
  --https               强制将 GitHub SSH 子模块 URL 按 HTTPS 拉取
  --non-interactive     跳过所有提示（传入 --public/--private 或模块参数时也会自动进入）
  -y, --yes             非交互确认（如清理将改由 deb 提供的源码目录）
  -h, --help            显示帮助

环境变量（命令行优先）:
  OPEN_DEPLOY_NONINTERACTIVE=1
  OPEN_DEPLOY_VISIBILITY=public|private
  OPEN_DEPLOY_LANG=zh|en
  OPEN_DEPLOY_OCS2=deb|source
  OPEN_DEPLOY_ARMS=deb|source
  OPEN_DEPLOY_COMMON=deb|source
  OPEN_DEPLOY_FLOW=init|switch|deb_only|deb_uninstall|rosdep
  OPEN_DEPLOY_GIT_HTTPS=1
  OPEN_DEPLOY_YES=1

SSH / HTTPS:
  .gitmodules 使用 git@github.com: SSH URL。无 ssh 二进制、或 public 模式且无可用
  SSH 密钥时，脚本会把 GitHub SSH URL 改写为 HTTPS 再 submodule sync/update。
  仅设置 git config url.https://github.com/.insteadOf git@github.com: 不足以
  保证 git submodule update 成功（嵌套仓读自己的 .gitmodules，且会直接走 ssh）。
  已有 SSH 密钥的 private 嵌套保持原 URL，不受影响。
EOF
}

ssh_keys_available() {
    if command -v ssh-add >/dev/null 2>&1 && ssh-add -l >/dev/null 2>&1; then
        return 0
    fi
    local f
    for f in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa" "${HOME}/.ssh/id_ecdsa" "${HOME}/.ssh/id_dsa"; do
        [ -f "$f" ] && return 0
    done
    return 1
}

should_use_https_fallback() {
    [ "${FORCE_HTTPS:-0}" -eq 1 ] && return 0
    if ! command -v ssh >/dev/null 2>&1; then
        return 0
    fi
    # GitHub 不允许匿名 SSH；public 克隆在没有密钥时应走 HTTPS
    if [ "${INIT_MODE}" = "public" ] && ! ssh_keys_available; then
        return 0
    fi
    return 1
}

github_ssh_to_https() {
    local url="$1"
    case "$url" in
        git@github.com:*)
            printf '%s\n' "https://github.com/${url#git@github.com:}"
            ;;
        ssh://git@github.com/*)
            printf '%s\n' "https://github.com/${url#ssh://git@github.com/}"
            ;;
        *)
            printf '%s\n' "$url"
            ;;
    esac
}

run_git() {
    if should_use_https_fallback; then
        # 只注入 scp 风格前缀；同一 key 的第二个 -c 会覆盖第一个。
        # 真正保证 submodule update 成功的是 prepare_repo_https_urls 改写 .gitmodules。
        git -c "url.https://github.com/.insteadOf=git@github.com:" "$@"
    else
        git "$@"
    fi
}

record_rewritten_repo() {
    local repo="$1" existing
    for existing in "${REWRITTEN_GITMODULES_REPOS[@]+"${REWRITTEN_GITMODULES_REPOS[@]}"}"; do
        [ "$existing" = "$repo" ] && return 0
    done
    REWRITTEN_GITMODULES_REPOS+=("$repo")
}

# 把仓库 .gitmodules 中的 GitHub SSH URL 改写成 HTTPS，并 sync 到 .git/config。
# 仅改工作区；结束后 restore，避免把 URL 变更提交进工作区。
# 单独设置 insteadOf 不够：嵌套 git submodule update 会按子仓 .gitmodules 直接调 ssh。
prepare_repo_https_urls() {
    local repo="$1"
    local gm="$repo/.gitmodules"
    local line key url new changed=0

    [ -f "$gm" ] || return 0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        key="${line%% *}"
        url="${line#* }"
        new="$(github_ssh_to_https "$url")"
        if [ "$new" != "$url" ]; then
            git config --file "$gm" "$key" "$new"
            changed=1
        fi
    done < <(git config --file "$gm" --get-regexp '^submodule\..*\.url$' 2>/dev/null || true)

    if [ "$changed" -eq 1 ]; then
        record_rewritten_repo "$repo"
        print_info "已将 $repo/.gitmodules 中的 GitHub SSH URL 改写为 HTTPS"
        git -C "$repo" submodule sync --quiet 2>/dev/null || true
    fi

    if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$repo" config --local "url.https://github.com/.insteadOf" "git@github.com:"
        git -C "$repo" config --local --add "url.https://github.com/.insteadOf" "ssh://git@github.com/" 2>/dev/null || true
    fi
}

restore_gitmodules_if_dirty() {
    local repo="$1"
    if [ ! -f "$repo/.gitmodules" ]; then
        return 0
    fi
    if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
        && ! git -C "$repo" diff --quiet -- .gitmodules 2>/dev/null; then
        git -C "$repo" checkout -- .gitmodules 2>/dev/null \
            || git -C "$repo" restore -- .gitmodules 2>/dev/null \
            || true
        print_info "已还原 $repo/.gitmodules（HTTPS 仅用于本次拉取，不改仓库记录）"
    fi
}

restore_all_rewritten_gitmodules() {
    local repo
    for repo in "${REWRITTEN_GITMODULES_REPOS[@]+"${REWRITTEN_GITMODULES_REPOS[@]}"}"; do
        restore_gitmodules_if_dirty "$repo"
    done
}

rewrite_origin_to_https_if_needed() {
    local url new
    should_use_https_fallback || return 0
    url="$(git remote get-url origin 2>/dev/null || true)"
    [ -n "$url" ] || return 0
    new="$(github_ssh_to_https "$url")"
    if [ "$new" != "$url" ]; then
        git remote set-url origin "$new"
        print_info "  origin 已改为 HTTPS: $new"
    fi
}

clear_colcon_ignore_for_init() {
    local path="$1"
    if path_is_git_checkout "$path"; then
        return 0
    fi
    if [ -f "$REPO_DIR/$path/COLCON_IGNORE" ]; then
        rm -f "$REPO_DIR/$path/COLCON_IGNORE"
        print_info "已移除 $path/COLCON_IGNORE 以便初始化嵌套子模块"
    fi
}

list_parent_nested_rel_paths() {
    local parent_dir="$1"
    local gm="$REPO_DIR/$parent_dir/.gitmodules"
    [ -f "$gm" ] || return 0
    git config --file "$gm" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}'
}

ensure_parent_ignores_colcon_ignore() {
    local parent_dir="$1"
    local git_dir exclude_file
    git_dir="$(git -C "$REPO_DIR/$parent_dir" rev-parse --git-dir 2>/dev/null || true)"
    [ -n "$git_dir" ] || return 0
    case "$git_dir" in
        /*) ;;
        *) git_dir="$REPO_DIR/$parent_dir/$git_dir" ;;
    esac
    exclude_file="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude_file")"
    if [ -f "$exclude_file" ] && grep -Eq '(^|/)COLCON_IGNORE$' "$exclude_file"; then
        return 0
    fi
    printf '%s\n' '**/COLCON_IGNORE' >> "$exclude_file"
}

# public 模式（以及任何未 init 的嵌套路径）：空的 private/hardware 目录会让 colcon 扫到垃圾
mark_uninitialized_nested_colcon_ignore() {
    local spec parent_dir rest relative_path full_path rel

    for parent_dir in src/arms_ros2_control src/ocs2_ros2 src/robot-descriptions; do
        [ -d "$REPO_DIR/$parent_dir" ] || continue
        path_is_git_checkout "$parent_dir" || continue
        while IFS= read -r rel; do
            [ -z "$rel" ] && continue
            full_path="$parent_dir/$rel"
            if path_is_git_checkout "$full_path"; then
                continue
            fi
            if [ -d "$REPO_DIR/$full_path" ] && [ ! -e "$REPO_DIR/$full_path/COLCON_IGNORE" ]; then
                touch "$REPO_DIR/$full_path/COLCON_IGNORE"
                ensure_parent_ignores_colcon_ignore "$parent_dir"
                print_info "已写入 COLCON_IGNORE: $full_path（未初始化的嵌套子模块，避免 colcon 扫描空目录）"
            fi
        done < <(list_parent_nested_rel_paths "$parent_dir")
    done

    if [ "$INIT_MODE" = "public" ]; then
        for spec in "${NESTED_PRIVATE_SPECS[@]+"${NESTED_PRIVATE_SPECS[@]}"}"; do
            parent_dir="${spec%%:*}"
            rest="${spec#*:}"
            relative_path="${rest#*:}"
            full_path="$parent_dir/$relative_path"
            if path_is_git_checkout "$full_path"; then
                continue
            fi
            if [ -d "$REPO_DIR/$full_path" ] && [ ! -e "$REPO_DIR/$full_path/COLCON_IGNORE" ]; then
                touch "$REPO_DIR/$full_path/COLCON_IGNORE"
                ensure_parent_ignores_colcon_ignore "$parent_dir"
                print_info "已写入 COLCON_IGNORE: $full_path（public 模式未初始化的 private 嵌套）"
            fi
        done
    fi
}

apply_env_overrides() {
    if env_truthy "${OPEN_DEPLOY_NONINTERACTIVE:-}"; then
        NONINTERACTIVE=1
    fi
    if env_truthy "${OPEN_DEPLOY_GIT_HTTPS:-}"; then
        FORCE_HTTPS=1
    fi
    if env_truthy "${OPEN_DEPLOY_YES:-}"; then
        ASSUME_YES=1
    fi
    if [ -z "$CLI_VIS" ] && [ -n "${OPEN_DEPLOY_VISIBILITY:-}" ]; then
        CLI_VIS="${OPEN_DEPLOY_VISIBILITY}"
        NONINTERACTIVE=1
    fi
    if [ -z "$CLI_LANG" ] && [ -n "${OPEN_DEPLOY_LANG:-}" ]; then
        CLI_LANG="$(normalize_ui_lang "${OPEN_DEPLOY_LANG}")" || {
            print_error "无效的 OPEN_DEPLOY_LANG=${OPEN_DEPLOY_LANG}（可用: zh, en）"
            exit 1
        }
    fi
    if [ -z "$CLI_FLOW" ] && [ -n "${OPEN_DEPLOY_FLOW:-}" ]; then
        CLI_FLOW="${OPEN_DEPLOY_FLOW}"
        NONINTERACTIVE=1
    fi
    local parsed
    if [ -z "$CLI_OCS2" ] && [ -n "${OPEN_DEPLOY_OCS2:-}" ]; then
        parsed="$(parse_ds_value "${OPEN_DEPLOY_OCS2}")" || {
            print_error "无效的 OPEN_DEPLOY_OCS2=${OPEN_DEPLOY_OCS2}（可用: deb, source）"
            exit 1
        }
        CLI_OCS2="$parsed"
        NONINTERACTIVE=1
    fi
    if [ -z "$CLI_ARMS" ] && [ -n "${OPEN_DEPLOY_ARMS:-}" ]; then
        parsed="$(parse_ds_value "${OPEN_DEPLOY_ARMS}")" || {
            print_error "无效的 OPEN_DEPLOY_ARMS=${OPEN_DEPLOY_ARMS}（可用: deb, source）"
            exit 1
        }
        CLI_ARMS="$parsed"
        NONINTERACTIVE=1
    fi
    if [ -z "$CLI_COMMON" ] && [ -n "${OPEN_DEPLOY_COMMON:-}" ]; then
        parsed="$(parse_ds_value "${OPEN_DEPLOY_COMMON}")" || {
            print_error "无效的 OPEN_DEPLOY_COMMON=${OPEN_DEPLOY_COMMON}（可用: deb, source）"
            exit 1
        }
        CLI_COMMON="$parsed"
        NONINTERACTIVE=1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --public)
            [ -n "$CLI_VIS" ] && [ "$CLI_VIS" != "public" ] && {
                print_error "不能同时指定 --public 与 --private"
                exit 1
            }
            CLI_VIS="public"
            NONINTERACTIVE=1
            shift
            ;;
        --private)
            [ -n "$CLI_VIS" ] && [ "$CLI_VIS" != "private" ] && {
                print_error "不能同时指定 --public 与 --private"
                exit 1
            }
            CLI_VIS="private"
            NONINTERACTIVE=1
            shift
            ;;
        --lang=*)
            CLI_LANG="$(normalize_ui_lang "${1#*=}")" || {
                print_error "无效的 --lang 值: ${1#*=}（可用: zh, en）"
                exit 1
            }
            shift
            ;;
        --ocs2=*)
            CLI_OCS2="$(parse_ds_value "${1#*=}")" || {
                print_error "无效的 --ocs2 值: ${1#*=}（可用: deb, source）"
                exit 1
            }
            NONINTERACTIVE=1
            shift
            ;;
        --arms=*)
            CLI_ARMS="$(parse_ds_value "${1#*=}")" || {
                print_error "无效的 --arms 值: ${1#*=}（可用: deb, source）"
                exit 1
            }
            NONINTERACTIVE=1
            shift
            ;;
        --common=*)
            CLI_COMMON="$(parse_ds_value "${1#*=}")" || {
                print_error "无效的 --common 值: ${1#*=}（可用: deb, source）"
                exit 1
            }
            NONINTERACTIVE=1
            shift
            ;;
        --ocs2)
            [ $# -ge 2 ] || { print_error "--ocs2 需要参数 deb|source"; exit 1; }
            CLI_OCS2="$(parse_ds_value "$2")" || {
                print_error "无效的 --ocs2 值: $2（可用: deb, source）"
                exit 1
            }
            NONINTERACTIVE=1
            shift 2
            ;;
        --arms)
            [ $# -ge 2 ] || { print_error "--arms 需要参数 deb|source"; exit 1; }
            CLI_ARMS="$(parse_ds_value "$2")" || {
                print_error "无效的 --arms 值: $2（可用: deb, source）"
                exit 1
            }
            NONINTERACTIVE=1
            shift 2
            ;;
        --common)
            [ $# -ge 2 ] || { print_error "--common 需要参数 deb|source"; exit 1; }
            CLI_COMMON="$(parse_ds_value "$2")" || {
                print_error "无效的 --common 值: $2（可用: deb, source）"
                exit 1
            }
            NONINTERACTIVE=1
            shift 2
            ;;
        --init)
            CLI_FLOW="init"
            NONINTERACTIVE=1
            shift
            ;;
        --switch)
            CLI_FLOW="switch"
            NONINTERACTIVE=1
            shift
            ;;
        --deb-only)
            CLI_FLOW="deb_only"
            NONINTERACTIVE=1
            shift
            ;;
        --deb-uninstall)
            CLI_FLOW="deb_uninstall"
            NONINTERACTIVE=1
            shift
            ;;
        --rosdep)
            CLI_FLOW="rosdep"
            NONINTERACTIVE=1
            shift
            ;;
        --only)
            [ $# -ge 2 ] || { print_error "--only 需要包列表"; exit 1; }
            CLI_ONLY="$(echo "$2" | tr -d '[:space:]')"
            shift 2
            ;;
        --https)
            FORCE_HTTPS=1
            shift
            ;;
        --non-interactive|--noninteractive)
            NONINTERACTIVE=1
            shift
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        *)
            print_error "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

apply_env_overrides

# 界面语言：命令行 / 环境变量 > 上次状态 > 默认 zh
load_ui_lang_from_state
if [ -n "$CLI_LANG" ]; then
    UI_LANG="$CLI_LANG"
fi

if [ -n "$CLI_FLOW" ]; then
    case "$CLI_FLOW" in
        init|switch|deb_only|deb_uninstall|rosdep) FLOW="$CLI_FLOW" ;;
        *)
            print_error "无效流程: $CLI_FLOW"
            exit 1
            ;;
    esac
fi
if [ -n "$CLI_VIS" ]; then
    case "$CLI_VIS" in
        public|private) INIT_MODE="$CLI_VIS" ;;
        *)
            print_error "无效可见性: $CLI_VIS（可用: public, private）"
            exit 1
            ;;
    esac
fi
[ -n "$CLI_OCS2" ] && USE_DEB_OCS2="$CLI_OCS2"
[ -n "$CLI_ARMS" ] && USE_DEB_ARMS="$CLI_ARMS"
[ -n "$CLI_COMMON" ] && USE_DEB_COMMON="$CLI_COMMON"

print_info "工作空间目录: $REPO_DIR"
cd "$REPO_DIR"

# 检查是否是 git 仓库
if [ ! -d ".git" ]; then
    print_error "当前目录不是 git 仓库！"
    print_info "请先克隆主仓库："
    print_info "  git clone https://github.com/fiveages-sim/open-deploy-ws.git ros2_ws"
    print_info "  # 或（已配置 SSH 密钥时）git clone git@github.com:fiveages-sim/open-deploy-ws.git ros2_ws"
    exit 1
fi

toggle_ui_lang() {
    if [ "$UI_LANG" = "en" ]; then
        UI_LANG="zh"
    else
        UI_LANG="en"
    fi
    # 仅更新语言字段，保留其它已保存的模块方式
    if [ -f "$MODE_STATE_FILE" ]; then
        if grep -qE '^UI_LANG=' "$MODE_STATE_FILE" 2>/dev/null; then
            sed -i "s/^UI_LANG=.*/UI_LANG=$UI_LANG/" "$MODE_STATE_FILE"
        else
            printf 'UI_LANG=%s\n' "$UI_LANG" >> "$MODE_STATE_FILE"
        fi
    else
        printf '# UI language only (module modes not chosen yet)\nUI_LANG=%s\n' "$UI_LANG" > "$MODE_STATE_FILE"
    fi
    msg lang_switched
}

# 选择流程（6 = 切换语言并重新显示菜单）
if [ "$NONINTERACTIVE" -eq 0 ]; then
    while true; do
        echo ""
        msg menu_title
        echo ""
        msg menu_1
        msg menu_1_hint
        msg menu_2
        msg menu_3
        msg menu_4
        msg menu_5
        msg menu_6
        echo ""
        read -rp "$(msg menu_prompt)" flow_choice
        case "$flow_choice" in
            2) FLOW="switch"; break ;;
            3) FLOW="deb_only"; break ;;
            4) FLOW="deb_uninstall"; break ;;
            5) FLOW="rosdep"; break ;;
            6|l|L)
                toggle_ui_lang
                continue
                ;;
            *) FLOW="init"; break ;;
        esac
    done
else
    print_info "非交互模式: flow=$FLOW, lang=$UI_LANG"
fi

# ---------- 快捷：仅 rosdep ----------
if [ "$FLOW" = "rosdep" ]; then
    print_info "模式: 仅运行 rosdep"
    echo ""
    run_rosdep_install || exit 1
    exit 0
fi

# ---------- 快捷：仅 deb / 卸载 ----------
if [ "$FLOW" = "deb_only" ]; then
    only_choice="$CLI_ONLY"
    if [ "$NONINTERACTIVE" -eq 0 ]; then
        echo ""
        msg deb_only_prompt_title
        echo "  ocs2, common, arms"
        read -rp "$(msg pkg_list_prompt)" only_choice
        only_choice="$(echo "$only_choice" | tr -d '[:space:]')"
    fi
    print_info "模式: 仅安装核心 deb 包（不拉取 Git 子模块）"
    echo ""
    run_install_core_debs "$only_choice" || exit 1
    print_info ""
    print_info "完成后请执行: source /opt/ros/jazzy/setup.bash"
    exit 0
fi

if [ "$FLOW" = "deb_uninstall" ]; then
    only_choice="$CLI_ONLY"
    if [ "$NONINTERACTIVE" -eq 0 ]; then
        echo ""
        msg deb_uninstall_prompt_title
        echo "  ocs2, common, arms"
        read -rp "$(msg pkg_list_prompt)" only_choice
        only_choice="$(echo "$only_choice" | tr -d '[:space:]')"
    fi
    print_info "模式: 卸载核心 deb 包"
    echo ""
    run_uninstall_core_debs "$only_choice" || exit 1
    exit 0
fi

# ---------- 可见性 + 模块方式（init / switch 共用提示） ----------
if [ "$FLOW" = "init" ]; then
    # 若有上次状态，仅用作模块方式默认值（命令行 / 环境变量优先）
    _def_ocs2=1
    _def_arms=0
    _def_common=0
    if [ -f "$MODE_STATE_FILE" ]; then
        _def_ocs2="$(grep -E '^USE_DEB_OCS2=' "$MODE_STATE_FILE" 2>/dev/null | cut -d= -f2- || echo 1)"
        _def_arms="$(grep -E '^USE_DEB_ARMS=' "$MODE_STATE_FILE" 2>/dev/null | cut -d= -f2- || echo 0)"
        _def_common="$(grep -E '^USE_DEB_COMMON=' "$MODE_STATE_FILE" 2>/dev/null | cut -d= -f2- || echo 0)"
        [[ "$_def_ocs2" =~ ^[01]$ ]] || _def_ocs2=1
        [[ "$_def_arms" =~ ^[01]$ ]] || _def_arms=0
        [[ "$_def_common" =~ ^[01]$ ]] || _def_common=0
        print_info "检测到上次选择: ocs2=$(mode_label "$_def_ocs2"), arms=$(mode_label "$_def_arms"), common=$(mode_label "$_def_common")"
    fi
    [ -n "$CLI_OCS2" ] && _def_ocs2="$CLI_OCS2"
    [ -n "$CLI_ARMS" ] && _def_arms="$CLI_ARMS"
    [ -n "$CLI_COMMON" ] && _def_common="$CLI_COMMON"
    USE_DEB_OCS2="$_def_ocs2"
    USE_DEB_ARMS="$_def_arms"
    USE_DEB_COMMON="$_def_common"

    # 先选 source/deb（全屏），再勾选嵌套（deb 对应父仓的嵌套不会出现在列表里）
    if [ "$NONINTERACTIVE" -eq 0 ]; then
        echo ""
        pick_core_module_modes
    fi

    echo ""
    ensure_nested_selection
fi

# switch 流程：仅对「安装方式真正变化」的模块动手；未改动的源码模块绝不 sync/update/pull/reset
CHANGED_OCS2=0
CHANGED_ARMS=0
CHANGED_COMMON=0

set_module_changed() {
    case "$1" in
        ocs2) CHANGED_OCS2="$2" ;;
        arms) CHANGED_ARMS="$2" ;;
        common) CHANGED_COMMON="$2" ;;
    esac
}

get_module_changed() {
    case "$1" in
        ocs2) echo "$CHANGED_OCS2" ;;
        arms) echo "$CHANGED_ARMS" ;;
        common) echo "$CHANGED_COMMON" ;;
        *) echo "0" ;;
    esac
}

# 当前有效安装方式：deb=1 / source=0（mixed 视为需要处理，按目标对齐）
current_use_deb_from_state() {
    case "$1" in
        deb) echo 1 ;;
        source) echo 0 ;;
        mixed) echo "mixed" ;;
        none) echo "none" ;;
        *) echo "none" ;;
    esac
}

if [ "$FLOW" = "switch" ]; then
    # 切换安装方式：不勾选嵌套子模块；若改回 source，按上次/CLI 可见性预设拉嵌套
    _saved_init="public"
    if [ -f "$MODE_STATE_FILE" ]; then
        _saved_init="$(grep -E '^INIT_MODE=' "$MODE_STATE_FILE" 2>/dev/null | cut -d= -f2- || echo public)"
        [ -z "$_saved_init" ] && _saved_init="public"
    fi
    if [ -z "$CLI_VIS" ]; then
        CLI_VIS="$_saved_init"
    fi
    INIT_MODE="$CLI_VIS"
    if [ "$VISIBILITY_LOADED" -eq 0 ]; then
        load_visibility_conf
    fi
    apply_visibility_preset "$CLI_VIS"

    echo ""
    msg current_module_state
    for m in ocs2 arms common; do
        p="$(module_short_to_path "$m")"
        pkg="$(module_short_to_deb "$m")"
        st="$(detect_module_state "$p" "$pkg")"
        print_info "  $m ($p): $st"
    done

    if [ "$NONINTERACTIVE" -eq 1 ]; then
        if [ -z "$CLI_OCS2" ] && [ -z "$CLI_ARMS" ] && [ -z "$CLI_COMMON" ]; then
            print_error "非交互 --switch 需要至少一个模块参数，例如 --ocs2=source"
            exit 1
        fi
        for m in ocs2 arms common; do
            p="$(module_short_to_path "$m")"
            pkg="$(module_short_to_deb "$m")"
            st="$(detect_module_state "$p" "$pkg")"
            cur_deb="$(current_use_deb_from_state "$st")"
            local_target=""
            case "$m" in
                ocs2) [ -n "$CLI_OCS2" ] && local_target="$CLI_OCS2" ;;
                arms) [ -n "$CLI_ARMS" ] && local_target="$CLI_ARMS" ;;
                common) [ -n "$CLI_COMMON" ] && local_target="$CLI_COMMON" ;;
            esac
            if [ -z "$local_target" ]; then
                case "$st" in
                    deb) local_target=1 ;;
                    *) local_target=0 ;;
                esac
                set_use_deb_for_module "$m" "$local_target"
                set_module_changed "$m" 0
                print_info "  → $m 保持 $st"
                continue
            fi
            set_use_deb_for_module "$m" "$local_target"
            if [ "$cur_deb" = "$local_target" ]; then
                set_module_changed "$m" 0
                print_info "  → $m 目标与当前一致 ($(mode_label "$local_target"))，跳过"
            else
                set_module_changed "$m" 1
                print_info "  → $m 将切换: $st → $(mode_label "$local_target")"
            fi
        done
    else
        echo ""
        msg switch_target_title
        msg switch_target_hint
        for m in ocs2 arms common; do
            p="$(module_short_to_path "$m")"
            pkg="$(module_short_to_deb "$m")"
            st="$(detect_module_state "$p" "$pkg")"
            cur_deb="$(current_use_deb_from_state "$st")"
            read -rp "  $m $(msg switch_target_prompt_suffix)=$st [s/d/K]: " tgt
            tgt="${tgt:-k}"
            local_target=""
            case "$tgt" in
                s|S|source) local_target=0 ;;
                d|D|deb) local_target=1 ;;
                *)
                    # 保持：沿用当前状态；mixed/none 默认偏向 source 以便后续可初始化
                    case "$st" in
                        deb) local_target=1 ;;
                        *) local_target=0 ;;
                    esac
                    # 明确保持且已是纯 deb/source → 不标记变更
                    if [ "$st" = "deb" ] || [ "$st" = "source" ]; then
                        set_use_deb_for_module "$m" "$local_target"
                        set_module_changed "$m" 0
                        continue
                    fi
                    ;;
            esac
            set_use_deb_for_module "$m" "$local_target"
            if [ "$cur_deb" = "$local_target" ]; then
                set_module_changed "$m" 0
                print_info "  → $m 目标与当前一致 ($(mode_label "$local_target"))，跳过"
            else
                set_module_changed "$m" 1
                print_info "  → $m 将切换: $st → $(mode_label "$local_target")"
            fi
        done
    fi

    # arms deb 硬依赖 ocs2/common 本地包；在「无变化提前退出」前纠偏
    if [ "$USE_DEB_ARMS" -eq 1 ]; then
        if [ "$USE_DEB_OCS2" -eq 0 ] || ! is_pkg_installed "$(module_short_to_deb ocs2)"; then
            if [ "$USE_DEB_OCS2" -eq 0 ]; then
                print_warn "arms=deb 依赖 ros-jazzy-ocs2，已自动将 ocs2 改为 deb"
                USE_DEB_OCS2=1
            fi
            if ! is_pkg_installed "$(module_short_to_deb ocs2)"; then
                CHANGED_OCS2=1
            fi
        fi
        if [ "$USE_DEB_COMMON" -eq 0 ] || ! is_pkg_installed "$(module_short_to_deb common)"; then
            if [ "$USE_DEB_COMMON" -eq 0 ]; then
                print_warn "arms=deb 依赖 ros-jazzy-robot-descriptions-common，已自动将 common 改为 deb"
                USE_DEB_COMMON=1
            fi
            if ! is_pkg_installed "$(module_short_to_deb common)"; then
                CHANGED_COMMON=1
            fi
        fi
    fi

    if [ "$CHANGED_OCS2" -eq 0 ] && [ "$CHANGED_ARMS" -eq 0 ] && [ "$CHANGED_COMMON" -eq 0 ]; then
        print_info "没有模块需要切换安装方式，仅保存可见性设置后退出。"
        save_module_mode_state
        exit 0
    fi
    echo ""
    _changed_list=()
    [ "$CHANGED_OCS2" -eq 1 ] && _changed_list+=("ocs2")
    [ "$CHANGED_ARMS" -eq 1 ] && _changed_list+=("arms")
    [ "$CHANGED_COMMON" -eq 1 ] && _changed_list+=("common")
    print_info "本次仅处理有变化的模块: $(IFS=,; echo "${_changed_list[*]}")"
    unset _changed_list
fi

# init 流程：视为三个核心模块都需要按选择对齐（保持原有全量初始化语义）
if [ "$FLOW" = "init" ]; then
    CHANGED_OCS2=1
    CHANGED_ARMS=1
    CHANGED_COMMON=1
fi

# init：arms=deb 时强制补齐 ocs2/common deb，避免 apt held broken packages
if [ "$FLOW" = "init" ] && [ "$USE_DEB_ARMS" -eq 1 ]; then
    if [ "$USE_DEB_OCS2" -eq 0 ]; then
        print_warn "arms=deb 依赖 ros-jazzy-ocs2，已自动将 ocs2 改为 deb"
        USE_DEB_OCS2=1
    fi
    if [ "$USE_DEB_COMMON" -eq 0 ]; then
        print_warn "arms=deb 依赖 ros-jazzy-robot-descriptions-common，已自动将 common 改为 deb"
        USE_DEB_COMMON=1
    fi
fi

print_info "嵌套子模块模式: $INIT_MODE（已选 ${#SELECTED_NESTED_SPECS[@]} 项）"
print_info "模块方式: ocs2=$(mode_label "$USE_DEB_OCS2"), arms=$(mode_label "$USE_DEB_ARMS"), common=$(mode_label "$USE_DEB_COMMON")"
echo ""

should_skip_top_submodule() {
    local path="$1"
    case "$path" in
        src/ocs2_ros2) [ "$USE_DEB_OCS2" -eq 1 ] && return 0 ;;
        src/arms_ros2_control) [ "$USE_DEB_ARMS" -eq 1 ] && return 0 ;;
    esac
    return 1
}

# switch/init 共用：该顶层路径是否需要本次 git 操作（仅「有变化且目标为 source」；robot-descriptions 仅当 common 有变化）
should_touch_top_submodule() {
    local path="$1"
    case "$path" in
        src/ocs2_ros2)
            [ "$CHANGED_OCS2" -eq 1 ] && [ "$USE_DEB_OCS2" -eq 0 ]
            return $?
            ;;
        src/arms_ros2_control)
            [ "$CHANGED_ARMS" -eq 1 ] && [ "$USE_DEB_ARMS" -eq 0 ]
            return $?
            ;;
        src/robot-descriptions)
            if [ "$FLOW" = "switch" ]; then
                # common→source：父仓已存在则不 sync/pull（只 init nested common）；缺失才 clone
                if [ "$CHANGED_COMMON" -eq 1 ] && [ "$USE_DEB_COMMON" -eq 0 ]; then
                    path_is_git_checkout "src/robot-descriptions" && return 1
                    return 0
                fi
                return 1
            fi
            # init：始终需要父仓（common 用 deb 时仍要其他模型包）
            return 0
            ;;
        *)
            # 未知顶层子模块：init 时照常处理，switch 时不动以免误伤
            [ "$FLOW" = "init" ]
            return $?
            ;;
    esac
}

should_skip_nested_path() {
    local relative_path="$1"
    if [ "$relative_path" = "common" ] && [ "$USE_DEB_COMMON" -eq 1 ]; then
        return 0
    fi
    return 1
}

should_skip_nested_spec() {
    local parent_dir="$1"
    local relative_path="$2"

    if [ "$FLOW" = "switch" ]; then
        case "$parent_dir" in
            src/ocs2_ros2)
                [ "$CHANGED_OCS2" -eq 1 ] && [ "$USE_DEB_OCS2" -eq 0 ] || return 0
                ;;
            src/arms_ros2_control)
                [ "$CHANGED_ARMS" -eq 1 ] && [ "$USE_DEB_ARMS" -eq 0 ] || return 0
                ;;
            src/robot-descriptions)
                # 切换 common→source 时只初始化 common，不碰其他模型子模块
                if [ "$CHANGED_COMMON" -eq 1 ] && [ "$USE_DEB_COMMON" -eq 0 ] \
                    && [ "$relative_path" = "common" ]; then
                    return 1
                fi
                return 0
                ;;
            *)
                return 0
                ;;
        esac
        return 1
    fi

    # init：父仓本身用 deb 时，其全部嵌套都跳过
    case "$parent_dir" in
        src/arms_ros2_control)
            [ "$USE_DEB_ARMS" -eq 1 ] && return 0
            ;;
        src/ocs2_ros2)
            [ "$USE_DEB_OCS2" -eq 1 ] && return 0
            ;;
    esac
    should_skip_nested_path "$relative_path"
}

remove_submodule_path() {
    local path="$1"
    print_info "清理源码目录: $path"

    case "$path" in
        src/robot-descriptions/common)
            if [ -d "$REPO_DIR/src/robot-descriptions" ]; then
                (cd "$REPO_DIR/src/robot-descriptions" && git submodule deinit -f -- common) \
                    2>/dev/null || print_warn "  deinit $path 失败，继续删除目录..."
            fi
            rm -rf "$REPO_DIR/$path"
            rm -rf "$REPO_DIR/.git/modules/src/robot-descriptions/modules/common" 2>/dev/null || true
            ;;
        *)
            git -C "$REPO_DIR" submodule deinit -f -- "$path" \
                2>/dev/null || print_warn "  deinit $path 失败，继续删除目录..."
            rm -rf "$REPO_DIR/$path"
            rm -rf "$REPO_DIR/.git/modules/$path" 2>/dev/null || true
            ;;
    esac
    print_info "✓ 已清理 $path"
}

cleanup_deb_module_sources() {
    local paths_to_clean=() p relative_path full_path clean_choice

    # 仅清理「本次改为 deb」的模块源码，避免误删未切换模块的本地修改
    [ "$CHANGED_OCS2" -eq 1 ] && [ "$USE_DEB_OCS2" -eq 1 ] && path_has_submodule_content "src/ocs2_ros2" && \
        paths_to_clean+=("src/ocs2_ros2")
    [ "$CHANGED_ARMS" -eq 1 ] && [ "$USE_DEB_ARMS" -eq 1 ] && path_has_submodule_content "src/arms_ros2_control" && \
        paths_to_clean+=("src/arms_ros2_control")
    if [ "$CHANGED_COMMON" -eq 1 ] && [ "$USE_DEB_COMMON" -eq 1 ]; then
        full_path="src/robot-descriptions/common"
        path_has_submodule_content "$full_path" && paths_to_clean+=("$full_path")
    fi

    if [ ${#paths_to_clean[@]} -eq 0 ]; then
        return 0
    fi

    print_warn "以下目录将改由 deb 提供，检测到已有源码内容："
    for p in "${paths_to_clean[@]}"; do
        print_warn "  - $p"
    done
    if [ "$NONINTERACTIVE" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ]; then
        print_info "非交互模式：清理上述将改由 deb 提供的源码目录"
        clean_choice="y"
    else
        read -rp "是否清理上述目录？[Y/n]: " clean_choice
    fi
    case "$clean_choice" in
        n|N|no|NO)
            print_warn "已跳过清理（可能仍占用磁盘，且可能与 deb 冲突）"
            return 0
            ;;
    esac

    for p in "${paths_to_clean[@]}"; do
        remove_submodule_path "$p"
    done
    echo ""
}

# 切换：仅对「本次改为 source」且仍装着 deb 的模块卸载
switch_uninstall_debs_for_source_targets() {
    local to_uninstall=()
    local m p pkg st
    for m in ocs2 arms common; do
        if [ "$(get_module_changed "$m")" -eq 1 ] && [ "$(get_use_deb_for_module "$m")" -eq 0 ]; then
            pkg="$(module_short_to_deb "$m")"
            if is_pkg_installed "$pkg"; then
                to_uninstall+=("$m")
            fi
        fi
    done
    if [ ${#to_uninstall[@]} -eq 0 ]; then
        return 0
    fi
    local IFS=,
    local list="${to_uninstall[*]}"
    print_info "以下模块改为源码，将先卸载对应 deb: $list"
    run_uninstall_core_debs "$list" || print_warn "部分 deb 卸载失败，继续尝试源码初始化..."
}

# 嵌套选择应已在 init/switch 提示阶段完成；兜底再应用一次预设
if [ "$VISIBILITY_LOADED" -eq 0 ] || [ ${#SELECTED_NESTED_SPECS[@]} -eq 0 ]; then
    ensure_nested_selection
fi
echo ""

if [ "$FLOW" = "switch" ]; then
    switch_uninstall_debs_for_source_targets
fi

cleanup_deb_module_sources

print_info "开始初始化子模块..."

# 正常结束与中断都还原 .gitmodules；INT/TERM 必须随后退出，避免半截 clone 后继续跑
restore_https_gitmodules_on_exit() {
    restore_all_rewritten_gitmodules
}
restore_https_gitmodules_on_signal() {
    restore_all_rewritten_gitmodules
    exit 130
}
trap restore_https_gitmodules_on_exit EXIT
trap restore_https_gitmodules_on_signal INT TERM

if should_use_https_fallback; then
    print_info "使用 HTTPS 拉取 GitHub 子模块（无 ssh / 无密钥 / --https）"
    prepare_repo_https_urls "$REPO_DIR"
fi

# 同步/初始化：仅处理本次需要拉源码的顶层路径
touch_paths=()
while IFS= read -r submodule_path; do
    should_touch_top_submodule "$submodule_path" || continue
    touch_paths+=("$submodule_path")
done < <(git config --file .gitmodules --get-regexp path | awk '{print $2}')

if [ ${#touch_paths[@]} -eq 0 ]; then
    print_info "本次无需拉取/更新任何顶层源码子模块"
else
    print_info "同步子模块配置（仅: ${touch_paths[*]})..."
    run_git submodule sync -- "${touch_paths[@]}"

    print_info "初始化顶层子模块（仅有变化且目标为 source）..."
    run_git submodule update --init -- "${touch_paths[@]}"
fi

# 遍历需要处理的源码子模块并切换到对应分支
print_info "将源码子模块切换到对应分支的最新提交..."

submodule_paths=$(git config --file .gitmodules --get-regexp path | awk '{print $2}')

repo_has_local_changes() {
    # 忽略仅子模块指针变化；有普通文件改动或未跟踪文件则视为脏（不自动 stash/reset）
    if ! git diff-files --quiet --ignore-submodules=all 2>/dev/null; then
        return 0
    fi
    if ! git diff-index --cached --quiet --ignore-submodules=all HEAD -- 2>/dev/null; then
        return 0
    fi
    if [ -n "$(git ls-files --others --exclude-standard 2>/dev/null | grep -Ev '(^|/)COLCON_IGNORE$')" ]; then
        return 0
    fi
    return 1
}

for submodule_path in $submodule_paths; do
    if ! should_touch_top_submodule "$submodule_path"; then
        if should_skip_top_submodule "$submodule_path"; then
            print_info "跳过子模块（deb 安装）: $submodule_path"
        else
            print_info "跳过子模块（本次未切换）: $submodule_path"
        fi
        continue
    fi
    branch_name=$(git config --file .gitmodules --get "submodule.$submodule_path.branch" || echo "main")

    if [ -d "$submodule_path" ]; then
        print_info "处理子模块: $submodule_path -> 分支: $branch_name"
        cd "$submodule_path"

        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            print_warn "子模块 $submodule_path 不是有效的 git 仓库，跳过"
            cd "$REPO_DIR"
            continue
        fi

        if repo_has_local_changes; then
            print_error "  检测到本地修改，跳过以免丢失工作。"
            print_error "  请先在该目录手动提交或 stash，再重新运行切换。"
            print_info "  目录: $REPO_DIR/$submodule_path"
            cd "$REPO_DIR"
            continue
        fi

        rewrite_origin_to_https_if_needed
        print_info "  获取远程更新..."
        run_git fetch origin || print_warn "  获取远程更新失败，继续..."

        if ! git ls-remote --exit-code --heads origin "$branch_name" > /dev/null 2>&1; then
            print_warn "  远程分支 $branch_name 不存在，跳过 $submodule_path"
            cd "$REPO_DIR"
            continue
        fi

        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

        if [ "$current_branch" = "$branch_name" ]; then
            print_info "  已在 $branch_name 分支"
        else
            print_info "  从 $current_branch 切换到 $branch_name 分支..."

            if [ "$current_branch" = "HEAD" ] || [ -z "$current_branch" ]; then
                if git show-ref --verify --quiet refs/heads/"$branch_name"; then
                    if ! git checkout "$branch_name" 2>/dev/null; then
                        print_error "  无法切换到 $branch_name 分支（工作区可能非干净），已跳过"
                        cd "$REPO_DIR"
                        continue
                    fi
                else
                    if ! git checkout -b "$branch_name" "origin/$branch_name" 2>/dev/null; then
                        print_error "  无法创建/切换到 $branch_name 分支，已跳过"
                        cd "$REPO_DIR"
                        continue
                    fi
                fi
            else
                if git show-ref --verify --quiet refs/heads/"$branch_name"; then
                    if ! git checkout "$branch_name" 2>/dev/null; then
                        print_error "  无法切换到 $branch_name 分支（工作区可能非干净），已跳过"
                        cd "$REPO_DIR"
                        continue
                    fi
                else
                    if ! git checkout -b "$branch_name" "origin/$branch_name" 2>/dev/null; then
                        print_error "  无法创建/切换到 $branch_name 分支，已跳过"
                        cd "$REPO_DIR"
                        continue
                    fi
                fi
            fi

            final_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
            if [ "$final_branch" != "$branch_name" ]; then
                print_error "  切换失败：当前仍在 $final_branch，目标分支是 $branch_name"
                cd "$REPO_DIR"
                continue
            fi
        fi

        print_info "  更新到最新提交..."
        run_git pull origin "$branch_name" || print_warn "  拉取更新失败"

        cd "$REPO_DIR"
        print_info "✓ $submodule_path 已切换到 $branch_name 分支"
    else
        print_warn "子模块路径不存在: $submodule_path"
    fi
done

# 初始化构建所需的嵌套子模块
print_info "初始化勾选的嵌套子模块..."
init_one_nested_submodule() {
    local parent_dir="$1"
    local relative_path="$2"
    if should_skip_nested_spec "$parent_dir" "$relative_path"; then
        print_info "跳过嵌套子模块（deb 安装）: $parent_dir/$relative_path"
        return 0
    fi
    [ ! -d "$parent_dir" ] && return 0
    if should_use_https_fallback; then
        prepare_repo_https_urls "$REPO_DIR/$parent_dir"
    fi
    clear_colcon_ignore_for_init "$parent_dir/$relative_path"
    (cd "$parent_dir" && run_git submodule update --init "$relative_path") \
        || print_warn "$parent_dir/$relative_path 初始化失败，跳过"
}

for spec in "${SELECTED_NESTED_SPECS[@]+"${SELECTED_NESTED_SPECS[@]}"}"; do
    [ -z "${spec:-}" ] && continue
    parent_dir="${spec%%:*}"
    rest="${spec#*:}"
    relative_path="${rest#*:}"
    init_one_nested_submodule "$parent_dir" "$relative_path"
done

print_info "将勾选的嵌套子模块切换到对应分支..."
for nested_spec in "${SELECTED_NESTED_SPECS[@]+"${SELECTED_NESTED_SPECS[@]}"}"; do
    [ -z "${nested_spec:-}" ] && continue
    parent_dir="${nested_spec%%:*}"
    rest="${nested_spec#*:}"
    gitmodules_file="${rest%%:*}"
    relative_path="${rest#*:}"
    if should_skip_nested_spec "$parent_dir" "$relative_path"; then
        continue
    fi
    full_path="$REPO_DIR/$parent_dir/$relative_path"
    if [ ! -d "$full_path" ]; then continue; fi
    if ! (cd "$full_path" && git rev-parse --git-dir >/dev/null 2>&1); then continue; fi
    gf="$REPO_DIR/$gitmodules_file"
    branch_name=$(git config --file "$gf" --get "submodule.$relative_path.branch" 2>/dev/null)
    if [ -z "$branch_name" ]; then
        config_key=$(git config --file "$gf" --get-regexp 'submodule\..*\.path' 2>/dev/null | awk -v p="$relative_path" '$2==p {k=$1; gsub(/^submodule\.|\.path$/,"",k); print k; exit}')
        branch_name=$(git config --file "$gf" --get "submodule.${config_key}.branch" 2>/dev/null)
    fi
    branch_name=${branch_name:-main}
    print_info "处理嵌套子模块: $parent_dir/$relative_path -> 分支: $branch_name"
    cd "$full_path"
    if repo_has_local_changes; then
        print_error "  检测到本地修改，跳过以免丢失工作: $parent_dir/$relative_path"
        cd "$REPO_DIR" || exit 1
        continue
    fi
    rewrite_origin_to_https_if_needed
    run_git fetch origin 2>/dev/null || print_warn "  获取远程更新失败，继续..."
    if git ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; then
        actual_branch="$branch_name"
    else
        actual_branch=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref: refs\/heads\// {sub(/refs\/heads\//,""); print $2; exit}')
        if [ -z "$actual_branch" ]; then
            print_warn "  远程分支 $branch_name 不存在且无法获取远程默认分支，跳过"
            cd "$REPO_DIR" || exit 1
            continue
        fi
        print_warn "  远程分支 $branch_name 不存在，改用远程默认分支: $actual_branch"
    fi
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    if [ "$current_branch" != "$actual_branch" ]; then
        if git show-ref --verify --quiet "refs/heads/$actual_branch"; then
            git checkout "$actual_branch" 2>/dev/null || {
                print_error "  无法切换到 $actual_branch，已跳过"
                cd "$REPO_DIR" || exit 1
                continue
            }
        else
            git checkout -b "$actual_branch" "origin/$actual_branch" 2>/dev/null || git checkout "$actual_branch" 2>/dev/null || {
                print_error "  无法创建/切换到 $actual_branch，已跳过"
                cd "$REPO_DIR" || exit 1
                continue
            }
        fi
    fi
    run_git pull origin "$actual_branch" 2>/dev/null || print_warn "  拉取更新失败"
    print_info "✓ $parent_dir/$relative_path 已切换到 $actual_branch 分支"
    cd "$REPO_DIR" || exit 1
done

restore_all_rewritten_gitmodules
mark_uninitialized_nested_colcon_ignore

print_info ""
print_info "=========================================="
print_info "子模块初始化完成！"
print_info "=========================================="
print_info ""
print_info "当前子模块状态："
git submodule status

# 安装 rosdep 依赖（仅对本次处理的源码路径）
print_info ""
print_info "安装 rosdep 依赖..."
if command -v rosdep >/dev/null 2>&1; then
    rosdep_paths=()
    while IFS= read -r submodule_path; do
        should_touch_top_submodule "$submodule_path" || continue
        rosdep_paths+=("$submodule_path")
    done < <(git config --file .gitmodules --get-regexp path | awk '{print $2}')
    if [ ${#rosdep_paths[@]} -gt 0 ]; then
        rosdep install --from-paths "${rosdep_paths[@]}" --ignore-src -r -y \
            || print_warn "rosdep 安装部分依赖失败，可稍后重试或检查 package.xml"
    else
        print_info "无源码路径需要 rosdep"
    fi
else
    print_warn "未找到 rosdep，请先安装 ROS 环境后手动运行："
    print_info "  cd $REPO_DIR && rosdep install --from-paths src --ignore-src -r -y"
fi

# 安装选中的 deb 包（switch 仅安装「本次改为 deb」的模块）
deb_only_parts=()
for m in ocs2 common arms; do
    if [ "$(get_use_deb_for_module "$m")" -eq 1 ]; then
        if [ "$FLOW" = "switch" ] && [ "$(get_module_changed "$m")" -eq 0 ]; then
            continue
        fi
        deb_only_parts+=("$m")
    fi
done
deb_only_list=""
if [ ${#deb_only_parts[@]} -gt 0 ]; then
    deb_only_list="$(IFS=,; echo "${deb_only_parts[*]}")"
fi
if [ -n "$deb_only_list" ]; then
    print_info ""
    run_install_core_debs "$deb_only_list" || print_error "deb 安装失败，请检查依赖（arms 需要 common+ocs2 deb）、deb_versions.conf 或网络连接"
fi

save_module_mode_state

print_info ""
print_info "后续步骤："
print_info "  1. source /opt/ros/jazzy/setup.bash"
if [ "$USE_DEB_OCS2" -eq 1 ] && [ "$USE_DEB_ARMS" -eq 1 ] && [ "$USE_DEB_COMMON" -eq 1 ]; then
    print_info "  2. 仅需编译 robot-descriptions 中的机器人模型包，例如："
    print_info "     colcon build --packages-up-to <robot>_description --symlink-install"
else
    print_info "  2. 按需 colcon build 编译源码模块"
fi
print_info ""
print_info "如需在源码与 deb 间切换，重新运行 ./init_repo.sh 并选择选项 2"
print_info "CI / 容器非交互示例: ./init_repo.sh --public --ocs2=deb --arms=source --common=source"
print_info "如需更新子模块到最新提交，可以运行："
print_info "  git submodule update --remote"
