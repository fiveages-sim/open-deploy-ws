#!/usr/bin/env bash

# 快速启动脚本（HT Deploy Workspace）
# - 自动识别当前 workspace 路径（脚本所在目录）
# - 支持机型切换：panthera_ht / openarm_ht（菜单或 ROBOT_NAME=...）
# - 拖动模式仅真机可用；仿真启动时不提供拖动模式
# - 启动选项参考：各 description 包 README.md

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${SCRIPT_DIR}"

. "${SCRIPT_DIR}/scripts/lib_common.sh"

# ===================== 常量 / 默认参数（集中在此，方便查看与修改） =====================

# 启动历史记忆文件（与 teleop_start.sh 共用；条目用 kind 字段区分）
HIST_FILE="${HOME}/.config/panthera_ht/quick_start_history.json"
# 当前机型记忆（菜单切换后持久化；环境变量 ROBOT_NAME 优先）
ROBOT_PREF_FILE="${HOME}/.config/panthera_ht/robot_name"
# 历史保留条数（最近 N 条不同配置）
HIST_MAX=2

# OCS2 启动包 / launch 文件 / 机器人名
OCS2_LAUNCH_PKG="ocs2_arm_controller"
OCS2_LAUNCH_FILE="demo.launch.py"

# 支持的机型列表（description 包名去掉 _description）
SUPPORTED_ROBOTS=(panthera_ht openarm_ht)

_load_robot_name() {
  local pref=""
  if [ -n "${ROBOT_NAME:-}" ]; then
    echo "${ROBOT_NAME}"
    return 0
  fi
  if [ -f "${ROBOT_PREF_FILE}" ]; then
    pref="$(tr -d '[:space:]' < "${ROBOT_PREF_FILE}" 2>/dev/null || true)"
  fi
  case "${pref}" in
    panthera_ht|openarm_ht) echo "${pref}" ;;
    *)
      # 默认：若存在 openarm 包则优先 openarm，否则 panthera
      if [ -d "${WS_DIR}/src/robot-descriptions-ht/openarm_ht_description" ]          || [ -d "${WS_DIR}/install/openarm_ht_description" ]; then
        echo "openarm_ht"
      else
        echo "panthera_ht"
      fi
      ;;
  esac
}

ROBOT_NAME="$(_load_robot_name)"

save_robot_name() {
  mkdir -p "$(dirname "${ROBOT_PREF_FILE}")"
  printf '%s\n' "${ROBOT_NAME}" > "${ROBOT_PREF_FILE}"
}

# 拖动模式（低刚度）kp/kd —— 按机型 DOF 生成（panthera=6, openarm=7；dual 时 xacro 自动拼接）
set_drag_gains_for_robot() {
  case "${ROBOT_NAME}" in
    openarm_ht)
      DRAG_JOINT_KP=(0.01 0.01 0.01 0.01 0.01 0.01 0.01)
      DRAG_JOINT_KD=(0.1 0.1 0.1 0.1 0.1 0.1 0.1)
      ;;
    *)
      DRAG_JOINT_KP=(0.01 0.01 0.01 0.01 0.01 0.01)
      DRAG_JOINT_KD=(0.1 0.1 0.1 0.1 0.1 0.1)
      ;;
  esac
  DRAG_GRIPPER_KP=0.001
  DRAG_GRIPPER_KD=0.01
}
set_drag_gains_for_robot

# 真机控制模式映射（菜单选项 → xacro_control_mode）
# 1) mit      — 位置+速度+力矩+kp/kd（kp/kd 可为 0）
# 2) effort   — 纯力矩（直接下发控制器 effort 命令）
# 3) position — 纯位置
declare -A CONTROL_MODES=(
  [1]="mit"
  [2]="effort"
  [3]="position"
)

# ===================== 安装模式判定：src 下有源码就编源码（源码优先） =====================
# 判定依据是「src 下是否真的存在包」，而不是「deb 是否装上了」：
#   - init_repo.sh 把模块切成 source 后，deb 可能仍残留安装着；
#     此时若只看 deb 就会误判成 deb 模式，导致源码 packages 一个都不编。
#   - 反过来，切成 deb 时子模块目录会被清空（只剩空目录），没有 package.xml，
#     此时才应判定为 deb 模式，只编 HT 描述包。
# 两者并存（mixed）时按源码编译：workspace overlay 会遮住同名 deb 包。

# 核心 deb 包名（arms 有 full / standard 两个变体，都算 arms deb）
ARMS_DEB_FULL="ros-jazzy-arms-ros2-control-full"
ARMS_DEB_STD="ros-jazzy-arms-ros2-control"

# 编译目标源码目录：仿真 / 真机共用（目录不存在或无 package.xml 自动跳过）
BUILD_SRC_DIRS_BASE=(arms_ros2_control ocs2_ros2 robot-descriptions-common robot-descriptions-ht)
# 真机额外需要的硬件驱动源码目录
BUILD_SRC_DIRS_REAL=(ht-ros2-control)

# 源码目录是否真的含包（deb 模式下子模块目录被清空，只剩空目录）
src_dir_has_pkgs() {
  [ -n "$(collect_pkgs "$1" "${WS_DIR}")" ]
}

# 收集待编译包名（去重）：$1 = sim | real
collect_build_pkgs() {
  local target="$1" d
  local -a dirs=("${BUILD_SRC_DIRS_BASE[@]}")
  [ "${target}" = "real" ] && dirs+=("${BUILD_SRC_DIRS_REAL[@]}")
  for d in "${dirs[@]}"; do
    collect_pkgs "${d}" "${WS_DIR}"
  done | sort -u
}

# 核心包（arms / ocs2 / robot-descriptions-common）是否有源码
core_src_mode() {
  src_dir_has_pkgs arms_ros2_control ||
    src_dir_has_pkgs ocs2_ros2 ||
    src_dir_has_pkgs robot-descriptions-common
}

# 核心包是否完全由 deb 提供（src 下确无源码时才算）
core_deb_mode() {
  core_src_mode && return 1
  return 0
}

# arms deb 是否已安装（full / standard 均算）
arms_deb_installed() {
  is_pkg_installed "${ARMS_DEB_FULL}" || is_pkg_installed "${ARMS_DEB_STD}"
}

# ht_ros2_control 是否由 arms-full deb 提供：src 下无源码、且 deb 已装
# src 下有 ht-ros2-control 源码时一律按源码编译（overlay 优先于 deb）
ht_from_deb() {
  src_dir_has_pkgs ht-ros2-control && return 1
  is_pkg_installed "${ARMS_DEB_FULL}"
}

source_ros_underlay() {
  if [ -f /opt/ros/jazzy/setup.bash ]; then
    # ROS2 ament 生成的 setup 脚本会引用未定义变量（如 AMENT_TRACE_SETUP_FILES、
    # AMENT_PYTHON_EXECUTABLE），在 set -u 下会报 "unbound variable"，
    # 因此 source 期间临时关闭 nounset
    set +u
    # shellcheck disable=SC1091
    source /opt/ros/jazzy/setup.bash
    set -u
    return 0
  fi
  echo -e "${YELLOW}[WARN] 未找到 /opt/ros/jazzy/setup.bash${NC}"
  return 1
}

source_workspace_env() {
  source_ros_underlay || return 1
  if [ -f "${WS_DIR}/install/setup.bash" ]; then
    # colcon 生成的 setup 脚本同样引用未定义变量（COLCON_TRACE 等），source 期间临时关闭
    set +u
    # shellcheck disable=SC1090
    source "${WS_DIR}/install/setup.bash"
    set -u
    echo -e "${GREEN}[INFO] 已 source 环境:${NC}"
    echo -e "${BLUE}  /opt/ros/jazzy/setup.bash${NC}"
    echo -e "${BLUE}  ${WS_DIR}/install/setup.bash${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] 未找到 ${WS_DIR}/install/setup.bash${NC}"
  return 1
}

ensure_ros_env() {
  if source_workspace_env; then
    return 0
  fi

  if core_deb_mode; then
    echo -e "${YELLOW}[WARN] deb 已提供核心控制包；请先编译 HT 包：${NC}"
    echo -e "${YELLOW}      ./quick_start.sh → 1) 编译${NC}"
    return 1
  fi

  echo -e "${YELLOW}[WARN] 请先在此 workspace 编译，然后再运行启动选项：${NC}"
  echo -e "${YELLOW}      cd ${WS_DIR} && colcon build --symlink-install${NC}"
  return 1
}

# ===================== 启动历史记忆 =====================
# 历史文件与 teleop_start.sh 共用；条目用 kind 字段区分：
#   quick_start 条目: 无 kind 或 kind=="quick_start"
#   teleop 条目:      kind=="teleop"
# 各脚本只统计/去重/重现自己 kind 的条目，互不干扰。

# 历史条数 (0/1/2)
history_count() {
  [ -f "${HIST_FILE}" ] || { echo 0; return 0; }
  python3 - "${HIST_FILE}" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = []
if not isinstance(d, list):
    d = []
d = [e for e in d if e.get("kind", "quick_start") == "quick_start"]
print(len(d))
PYEOF
}

# 第 idx 条历史的描述 (idx: 0=最近, 1=次近)
hist_desc_at() {
  python3 - "${HIST_FILE}" "$1" <<'PYEOF'
import json, sys
path, idx = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(path))
except Exception:
    d = []
if not isinstance(d, list):
    d = []
d = [e for e in d if e.get("kind", "quick_start") == "quick_start"]
if idx < len(d):
    print(d[idx].get("desc", ""))
PYEOF
}

# 记录一次启动配置 (按 type/hardware/control_mode/drag/usb_select 去重,
# 保留最近 HIST_MAX 条不同配置；其他 kind 条目原样保留)
record_launch() {
  python3 - "${HIST_FILE}" "$1" "$2" "$3" "$4" "$5" "${ROBOT_NAME}" "${HIST_MAX}" <<'PYEOF'
import json, os, sys, time
path, jtype, jhw, jcm, jdrag, jusb, robot, hist_max = sys.argv[1:9]
hist_max = int(hist_max)
drag = (jdrag == "true")
entry = {
    "kind": "quick_start",
    "robot": robot,
    "type": jtype,
    "hardware": jhw,
    "control_mode": jcm,
    "drag": drag,
    "usb_select": jusb,
    "ts": int(time.time()),
}
type_label = {"single": "单臂", "dual": "双臂", "left": "左臂", "right": "右臂"}.get(jtype, jtype)
robot_label = {"panthera_ht": "Panthera", "openarm_ht": "OpenArm"}.get(robot, robot)
parts = [robot_label, type_label,
         {"real": "真机", "isaac": "Isaac", "mock_components": "仿真"}.get(jhw, jhw)]
if jcm:
    parts.append(jcm)
if drag:
    parts.append("拖动")
if jusb and jusb != "auto":
    parts.append(f"盒:{jusb}")
entry["desc"] = " · ".join(parts)
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, list):
        data = []
except Exception:
    data = []

def same(e):
    return (e.get("robot", robot) == entry["robot"]
            and e.get("type") == entry["type"] and e.get("hardware") == entry["hardware"]
            and e.get("control_mode", "") == entry["control_mode"]
            and bool(e.get("drag", False)) == drag
            and e.get("usb_select", "auto") == jusb)

# 分离本 kind 与其他 kind 条目；只对本 kind 去重并限条数
qs = [e for e in data if e.get("kind", "quick_start") == "quick_start"]
other = [e for e in data if e.get("kind", "quick_start") != "quick_start"]
qs = [e for e in qs if not same(e)]
qs.insert(0, entry)
qs = qs[:hist_max]
data = qs + other
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF
}

# 主菜单: $1 = 历史条数 (0/1/2); 有历史时选项 1..N 为历史启动, 回车默认选 1
menu() {
  local n="${1:-0}"
  local last d
  echo -e "${BLUE}========================================${NC}" >&2
  echo -e "${BLUE}  快速启动（HT Deploy Workspace）${NC}" >&2
  echo -e "${BLUE}  Workspace: ${WS_DIR}${NC}" >&2
  echo -e "${BLUE}  Robot: ${ROBOT_NAME}${NC}" >&2
  echo -e "${BLUE}========================================${NC}" >&2
  echo "" >&2
  echo "请选择操作:" >&2
  if [ "${n}" -ge 1 ]; then
    d="$(hist_desc_at 0)"
    echo " *1) 上次启动: ${d}" >&2
  fi
  if [ "${n}" -ge 2 ]; then
    d="$(hist_desc_at 1)"
    echo "  $((n + 0))) 另一次启动: ${d}" >&2
  fi
  echo "  $((n + 1))) 编译 (Build)" >&2
  echo "  $((n + 2))) 启动 (Launch)" >&2
  echo "  0) 退出 (Exit)" >&2
  echo "" >&2
  last=$((n + 2))
  read -r -p "请输入选项 [0-${last}]（回车=默认 1）: " choice
  if [ -z "${choice}" ]; then
    choice="1"
  fi
  echo "${choice}"
}

robot_menu() {
  local default_choice="1"
  case "${ROBOT_NAME}" in
    openarm_ht) default_choice="2" ;;
    *) default_choice="1" ;;
  esac
  echo "" >&2
  echo -e "${BLUE}========================================${NC}" >&2
  echo -e "${BLUE}  选择机型 (当前: ${ROBOT_NAME})${NC}" >&2
  echo -e "${BLUE}========================================${NC}" >&2
  if [ "${default_choice}" = "1" ]; then
    echo " *1) panthera_ht   — Panthera HT（6-DoF 单臂/双臂）" >&2
    echo "  2) openarm_ht    — OpenArm HT（7-DoF 双臂底座）" >&2
  else
    echo "  1) panthera_ht   — Panthera HT（6-DoF 单臂/双臂）" >&2
    echo " *2) openarm_ht    — OpenArm HT（7-DoF 双臂底座）" >&2
  fi
  echo "  0) 退出" >&2
  echo "" >&2
  read -r -p "请输入选项 [0-2]（回车=默认 ${default_choice}）: " choice
  if [ -z "${choice}" ]; then
    choice="${default_choice}"
  fi
  echo "${choice}"
}

apply_robot_choice() {
  local choice="$1"
  case "${choice}" in
    1) ROBOT_NAME="panthera_ht" ;;
    2) ROBOT_NAME="openarm_ht" ;;
    0)
      echo "退出"
      exit 0
      ;;
    *)
      echo -e "${YELLOW}无效选项${NC}"
      exit 1
      ;;
  esac
  set_drag_gains_for_robot
  save_robot_name
  echo -e "${GREEN}机型: ${ROBOT_NAME}${NC}"
}

build_menu() {
  echo "" >&2
  echo "请选择编译目标:" >&2
  if core_src_mode; then
    echo -e "  ${GREEN}[检测到 src 下有源码，将编译源码包]${NC}" >&2
  else
    echo -e "  ${YELLOW}[src 下无核心包源码（deb 提供），只编译 workspace 内的包]${NC}" >&2
  fi
  if arms_deb_installed && core_src_mode; then
    echo -e "  ${YELLOW}[警告] arms deb 与源码并存，源码 overlay 会遮住 deb${NC}" >&2
  fi
  echo "  1) 编译仿真所需包" >&2
  echo "  2) 编译真机所需包" >&2
  echo "  0) 返回" >&2
  echo "" >&2
  read -r -p "请输入选项 [0-2]（回车=默认 1）: " choice
  if [ -z "${choice}" ]; then
    choice="1"
  fi
  echo "${choice}"
}

# 编译：$1 = sim | real
# 只编 src 下真实存在的包（deb 提供的模块目录为空，自动跳过），
# 用 --packages-up-to 顺带把工作空间内的依赖一并编出来。
do_build() {
  local target="$1"
  local -a pkgs=()

  mapfile -t pkgs < <(collect_build_pkgs "${target}")

  if [ "${#pkgs[@]}" -eq 0 ]; then
    echo -e "${RED}[ERROR] 未在 ${WS_DIR}/src 下找到任何可编译的包${NC}"
    return 1
  fi

  if core_src_mode; then
    echo -e "${BLUE}  模式: 源码编译（src 下有包）${NC}"
  else
    echo -e "${BLUE}  模式: 核心包由 deb 提供，仅编译 workspace 内包${NC}"
  fi
  echo -e "${BLUE}  编译包 (${#pkgs[@]}): ${pkgs[*]}${NC}"

  run_colcon_build --packages-up-to "${pkgs[@]}" --symlink-install
}

launch_menu() {
  echo "" >&2
  echo "请选择启动项:" >&2
  echo " *1) 双臂 (dual)" >&2
  echo "  2) 单臂 (single)" >&2
  echo "  3) 左臂 (left)" >&2
  echo "  4) 右臂 (right)" >&2
  echo "  5) 手柄遥操作" >&2
  echo "  0) 返回" >&2
  echo "" >&2
  read -r -p "请输入选项 [0-5]（回车=默认 1）: " choice
  if [ -z "${choice}" ]; then
    choice="1"
  fi
  echo "${choice}"
}

launch_mode_menu() {
  echo "" >&2
  echo "请选择运行模式:" >&2
  echo " *1) 仿真 (mock_components)" >&2
  echo "  2) 真机" >&2
  echo "  3) Isaac 仿真 (hardware:=isaac)" >&2
  echo "  0) 返回" >&2
  echo "" >&2
  read -r -p "请输入选项 [0-3]（回车=默认 1）: " choice
  if [ -z "${choice}" ]; then
    choice="1"
  fi
  echo "${choice}"
}

# Real-hardware HI control mode (passed as xacro_control_mode → robot.xacro control_mode)
control_mode_menu() {
  echo "" >&2
  echo "请选择真机控制模式:" >&2
  echo " *1) mit      — 位置+速度+力矩+kp/kd（kp/kd 可为 0）" >&2
  echo "  2) effort   — 纯力矩（直接下发控制器 effort 命令）" >&2
  echo "  3) position — 纯位置" >&2
  echo "  0) 返回" >&2
  echo "" >&2
  read -r -p "请输入选项 [0-3]（回车=默认 1）: " choice
  if [ -z "${choice}" ]; then
    choice="1"
  fi
  echo "${choice}"
}

# Maps menu choice → control_mode string; empty means back/cancel
resolve_control_mode() {
  case "$1" in
    0) echo "" ;;
    *)
      if [ -n "${CONTROL_MODES[$1]:-}" ]; then
        echo "${CONTROL_MODES[$1]}"
      else
        echo "INVALID"
      fi
      ;;
  esac
}

# Real hardware: check /dev/ttyACM* and grant rw if needed.
ensure_ttyacm_access() {
  local devices=()
  local d

  echo -e "${BLUE}[INFO] 检查电机串口 /dev/ttyACM* ...${NC}"
  shopt -s nullglob
  devices=(/dev/ttyACM*)
  shopt -u nullglob

  if [ ${#devices[@]} -eq 0 ]; then
    echo -e "${RED}[ERROR] 未找到 /dev/ttyACM* 设备${NC}"
    echo -e "${YELLOW}      请检查 USB 连接、供电，以及 Panthera.yaml 中 Serial_Type=/dev/ttyACM${NC}"
    echo -e "${YELLOW}      排查: ls /dev/ttyACM*${NC}"
    read -r -p "仍要继续启动真机吗？[y/N]: " cont
    case "${cont}" in
      y|Y|yes|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi

  echo -e "${GREEN}[INFO] 发现串口设备:${NC}"
  for d in "${devices[@]}"; do
    echo -e "${BLUE}  ${d}${NC}"
  done

  for d in "${devices[@]}"; do
    if [ -r "${d}" ] && [ -w "${d}" ]; then
      continue
    fi
    echo -e "${YELLOW}[INFO] ${d} 无读写权限，尝试: sudo chmod a+rw ${d}${NC}"
    if ! sudo chmod a+rw "${d}"; then
      echo -e "${RED}[ERROR] 无法设置 ${d} 权限${NC}"
      return 1
    fi
  done

  echo -e "${GREEN}[INFO] 串口权限正常${NC}"
  return 0
}

# 询问是否启用拖动模式（低刚度，仅真机）；echo "true"/"false"
ask_drag_mode() {
  local yn
  read -r -p "启用拖动模式(低刚度, 夹爪可掰动)? [y/N]: " yn
  case "${yn}" in
    y|Y|yes|YES) echo "true" ;;
    *) echo "false" ;;
  esac
}

# 拖动模式: 生成低刚度 kp/kd 的 hardware_ 前缀参数（启动时经 xacro 直接写入
# URDF <param>，硬件加载即生效；无需启动后再调参数服务器）
# 每臂 N 值 CSV（panthera=6 / openarm=7）；dual 时 xacro 自动拼接
# 仅 hardware:=real/real_usb 时 hardware_ 前缀才生效（build_xacro_mappings）
drag_mode_args() {
  # 用当前机型拖动增益数组拼接 CSV
  local kp kd
  kp="$(IFS=', '; echo "${DRAG_JOINT_KP[*]}")"
  kd="$(IFS=', '; echo "${DRAG_JOINT_KD[*]}")"
  echo "hardware_joint_kp:=${kp} hardware_joint_kd:=${kd} hardware_gripper_kp:=${DRAG_GRIPPER_KP} hardware_gripper_kd:=${DRAG_GRIPPER_KD}"
}

# 重现一条历史启动配置 (idx: 0=最近, 1=次近)
run_history_launch() {
  local idx="$1"
  local jtype jhw jcm jdrag jusb jrobot
  IFS=',' read -r jtype jhw jcm jdrag jusb jrobot <<EOF
$(python3 - "${HIST_FILE}" "${idx}" <<'PYEOF'
import json, sys
path, idx = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(path))
except Exception:
    d = []
if not isinstance(d, list):
    d = []
d = [e for e in d if e.get("kind", "quick_start") == "quick_start"]
if idx >= len(d):
    print("single,mock_components,,false,auto,panthera_ht")
    sys.exit(0)
e = d[idx]
print(",".join([
    e.get("type", "single"),
    e.get("hardware", "mock_components"),
    e.get("control_mode", ""),
    "true" if e.get("drag") else "false",
    e.get("usb_select", "auto"),
    e.get("robot", "panthera_ht"),
]))
PYEOF
)
EOF
  if [ -n "${jrobot}" ]; then
    ROBOT_NAME="${jrobot}"
    set_drag_gains_for_robot
  fi
  local -a args=()
  args+=("type:=${jtype}")
  if [ "${jhw}" = "real" ]; then
    CONTROL_MODE="${jcm}"
    USB_SELECT="${jusb}"
    args+=("hardware:=real")
  elif [ "${jhw}" = "isaac" ]; then
    CONTROL_MODE=""
    USB_SELECT="auto"
    args+=("hardware:=isaac")
  else
    CONTROL_MODE=""
    USB_SELECT="auto"
  fi
  local label
  label="$(hist_desc_at "${idx}")"
  _run_ocs2_demo "${label}" "${jdrag}" "${args[@]}"
}

# 列出当前检测到的控制盒（按 USB 设备路径去重）
# 输出格式: 每行 "ID_PATH|样例口"（ID_PATH 如 pci-0000:00:14.0-usb-0:1.2，已去掉接口段）
detect_usb_boxes() {
  shopt -s nullglob
  local p path box
  declare -A seen
  for p in /dev/ttyACM*; do
    path="$(udevadm info -q property -n "${p}" 2>/dev/null | awk -F= '/^ID_PATH=/{print $2; exit}')"
    [ -n "${path}" ] || continue
    # 去掉接口段（如末尾 :1.0），只保留控制盒自身的 USB 路径（一盒一行）
    box="$(printf '%s' "${path}" | sed -E 's/:[0-9]+\.[0-9]+$//')"
    if [ -z "${seen[${box}]:-}" ]; then
      seen[${box}]="1"
      echo "${box}|${p}"
    fi
  done
  shopt -u nullglob
}

# 询问选择控制盒（多套机械臂同机时）；echo "auto" 或 USB 路径，或 "back"
ask_usb_select() {
  local boxes=() paths=() i=1 choice
  echo "" >&2
  echo "请选择控制盒 (USB 设备):" >&2
  echo " *0) 自动检测（仅 1 个控制盒时自动连接；多个时启动会报错并列出路径）" >&2
  while IFS='|' read -r path dev; do
    paths+=("${path}")
    echo "  ${i}) ${path}   (样例口: ${dev})" >&2
    i=$((i + 1))
  done < <(detect_usb_boxes)
  if [ "${i}" -eq 1 ]; then
    echo "  （当前未检测到 /dev/ttyACM*，请检查 USB 连接与供电）" >&2
  fi
  echo "  q) 返回" >&2
  echo "" >&2
  read -r -p "请输入选项 [0-$((${#paths[@]}))]（回车=默认 0）: " choice
  if [ -z "${choice}" ]; then
    choice="0"
  fi
  case "${choice}" in
    0) echo "auto" ;;
    q|Q) echo "back" ;;
    *)
      if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#paths[@]}" ]; then
        echo "${paths[$((choice - 1))]}"
      else
        echo -e "${YELLOW}无效选项，使用自动检测${NC}" >&2
        echo "auto"
      fi
      ;;
  esac
}

# Launch ocs2 demo. Args: arm_label drag_flag type_args...
# Uses CONTROL_MODE / USB_SELECT env if set (real only). Records the launch config to history.
_run_ocs2_demo() {
  local arm_label="$1" jdrag="$2"
  shift 2
  local -a extra_args=("$@")
  local mode_label=""
  local arg
  local jtype="single" jhw="mock_components" jcm="${CONTROL_MODE:-}" jusb="${USB_SELECT:-auto}"

  ensure_ros_env || exit 1

  for arg in "${extra_args[@]}"; do
    if [ "${arg}" = "hardware:=real" ]; then
      ensure_ttyacm_access || exit 1
      break
    fi
  done

  if [ -n "${CONTROL_MODE:-}" ]; then
    extra_args+=("xacro_control_mode:=${CONTROL_MODE}")
    mode_label="，控制模式=${CONTROL_MODE}"
  fi

  # 控制盒选择：非 auto 时追加 xacro_usb_select:=（motor_cpp 驱动层过滤）
  if [ "${jusb}" != "auto" ]; then
    extra_args+=("xacro_usb_select:=${jusb}")
    mode_label="${mode_label}，控制盒=${jusb}"
  fi

  # 解析本次启动配置并写入历史
  for arg in "${extra_args[@]}"; do
    case "${arg}" in
      type:=single) jtype="single" ;;
      type:=dual) jtype="dual" ;;
      type:=left) jtype="left" ;;
      type:=right) jtype="right" ;;
      hardware:=real) jhw="real" ;;
      hardware:=isaac) jhw="isaac" ;;
      hardware:=mock_components) jhw="mock_components" ;;
    esac
  done
  record_launch "${jtype}" "${jhw}" "${jcm}" "${jdrag}" "${jusb}"

  echo -e "${GREEN}启动${arm_label}${mode_label}...${NC}"
  if [ "${jdrag}" = "true" ]; then
    # 拖动模式：低刚度 kp/kd 作为 hardware_ 参数直接传入（xacro 展开进 URDF <param>）
    local -a drag_args
    read -r -a drag_args <<< "$(drag_mode_args "${jtype}")"
    echo -e "${BLUE}[INFO] 拖动模式：低刚度 kp/kd 已作为启动参数传入${NC}"
    ros2 launch "${OCS2_LAUNCH_PKG}" "${OCS2_LAUNCH_FILE}" robot:=${ROBOT_NAME} "${extra_args[@]}" "${drag_args[@]}"
  else
    ros2 launch "${OCS2_LAUNCH_PKG}" "${OCS2_LAUNCH_FILE}" robot:=${ROBOT_NAME} "${extra_args[@]}"
  fi
}

_joystick_enumerate_devices() {
  if ! command -v ros2 >/dev/null 2>&1; then
    return 1
  fi
  ros2 run joy joy_enumerate_devices 2>/dev/null
}

_joystick_count() {
  local count
  count="$(_joystick_enumerate_devices | grep -cE '^[[:space:]]*[0-9]+[[:space:]]*:' 2>/dev/null)" || count=0
  echo "${count}"
}

_joystick_first_id() {
  local device_id
  device_id="$(_joystick_enumerate_devices | awk -F ':' '/^[[:space:]]*[0-9]+[[:space:]]*:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1; exit}')"
  echo "${device_id:-0}"
}

_run_joystick_teleop_launch() {
  local joy_dev="${1:-}"
  ensure_ros_env || exit 1
  if [ -z "${joy_dev}" ]; then
    echo -e "${GREEN}启动手柄遥操作...${NC}"
    ros2 launch arms_teleop joystick_teleop.launch.py
  else
    echo -e "${GREEN}启动手柄遥操作（${joy_dev}）...${NC}"
    ros2 launch arms_teleop joystick_teleop.launch.py "joy_dev:=${joy_dev}"
  fi
}

joystick_device_menu() {
  local menu_lines
  echo "" >&2
  echo "请选择手柄设备:" >&2
  menu_lines="$(_joystick_enumerate_devices | awk -F ':' '/^[[:space:]]*[0-9]+[[:space:]]*:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); printf "  %s) %s\n", $1, $5}')"
  if [ -n "${menu_lines}" ]; then
    echo "${menu_lines}" >&2
  else
    echo " *0) Joy ID 0（未枚举到手柄，使用默认 ID）" >&2
  fi
  echo "  q) 返回" >&2
  echo "" >&2
  read -r -p "请输入 Joy ID（默认: 0，输入 q 返回）: " choice
  if [ -z "${choice}" ]; then
    choice="0"
  fi
  if [ "${choice}" = "q" ] || [ "${choice}" = "Q" ]; then
    choice="back"
  fi
  echo "${choice}"
}

do_launch_joystick_teleop() {
  local device_choice device_count device_id

  ensure_ros_env || exit 1
  device_count="$(_joystick_count)"

  if [ "${device_count}" -eq 1 ]; then
    device_id="$(_joystick_first_id)"
    if [ "${device_id}" = "0" ]; then
      _run_joystick_teleop_launch ""
    else
      _run_joystick_teleop_launch "/dev/input/js${device_id}"
    fi
    return
  fi

  device_choice="$(joystick_device_menu)"

  case "${device_choice}" in
    back)
      echo "返回"
      return
      ;;
    0)
      _run_joystick_teleop_launch ""
      ;;
    *)
      if ! [[ "${device_choice}" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}无效 Joy ID: ${device_choice}${NC}"
        exit 1
      fi
      _run_joystick_teleop_launch "/dev/input/js${device_choice}"
      ;;
  esac
}

run_colcon_build() {
  cd "${WS_DIR}" || exit 1
  source_ros_underlay
  colcon build "$@"
}

need_cmd colcon || echo -e "${YELLOW}[WARN] 未找到 colcon，编译选项会失败（通常需要安装 ROS 发行版环境）。${NC}"

# 机型选择放在最前，选定后进入编译/启动流程（一次跑完）
robot_choice="$(robot_menu)"
apply_robot_choice "${robot_choice}"

HIST_COUNT="$(history_count)"
top_choice="$(menu "${HIST_COUNT}")"

case "${top_choice}" in
  0)
    echo "退出"
    exit 0
    ;;
esac

# 历史记忆入口: [1..HIST_COUNT] 为历史启动; 之后依次为 编译 / 启动
if [ "${HIST_COUNT}" -ge 1 ] && [ "${top_choice}" -ge 1 ] && [ "${top_choice}" -le "${HIST_COUNT}" ]; then
  run_history_launch $((top_choice - 1))
  exit 0
fi

if [ "${top_choice}" = "$((HIST_COUNT + 1))" ]; then
    build_choice="$(build_menu)"
    case "${build_choice}" in
      1|2)
        if [ "${build_choice}" = "1" ]; then
          echo -e "${GREEN}开始编译仿真所需包...${NC}"
          if ! do_build sim; then
            echo -e "${YELLOW}编译过程中出现错误${NC}"
            exit 1
          fi
        else
          echo -e "${GREEN}开始编译真机所需包...${NC}"
          if ! do_build real; then
            echo -e "${YELLOW}编译过程中出现错误${NC}"
            exit 1
          fi
        fi
        echo -e "${GREEN}编译完成！${NC}"
        source_workspace_env || echo -e "${YELLOW}[WARN] workspace overlay 未加载，请检查 install/setup.bash${NC}"
        ;;
      0)
        echo "返回"
        ;;
      *)
        echo -e "${YELLOW}无效选项${NC}"
        exit 1
        ;;
    esac
    exit 0
fi

if [ "${top_choice}" = "$((HIST_COUNT + 2))" ]; then
    launch_choice="$(launch_menu)"
    case "${launch_choice}" in
      1|2|3|4)
        # type: dual/single/left/right（panthera_ht / openarm_ht 均支持）
        case "${launch_choice}" in
          1) arm_label="双臂"; type_arg="type:=dual" ;;
          2) arm_label="单臂"; type_arg="type:=single" ;;
          3) arm_label="左臂"; type_arg="type:=left" ;;
          4) arm_label="右臂"; type_arg="type:=right" ;;
        esac

        mode_choice="$(launch_mode_menu)"

        case "${mode_choice}" in
          1)
            # 仿真：mock_components，无拖动模式
            _run_ocs2_demo "${arm_label}仿真" "false" "${type_arg}"
            ;;
          2)
            # 真机：可启用拖动模式（低刚度，启动后调低硬件 kp/kd）
            drag_flag="false"
            if [ "$(ask_drag_mode)" = "true" ]; then
              drag_flag="true"
              echo -e "${BLUE}[INFO] 拖动模式已启用（低刚度）${NC}"
            fi
            cm_choice="$(control_mode_menu)"
            CONTROL_MODE="$(resolve_control_mode "${cm_choice}")"
            if [ "${CONTROL_MODE}" = "INVALID" ]; then
              echo -e "${YELLOW}无效选项${NC}"
              exit 1
            fi
            if [ -z "${CONTROL_MODE}" ]; then
              echo "返回"
            else
              # 控制盒选择：多套机械臂同机时指定本启动连接哪个控制盒
              USB_SELECT="$(ask_usb_select)"
              if [ "${USB_SELECT}" = "back" ]; then
                echo "返回"
              else
                if [ "${USB_SELECT}" = "auto" ]; then
                  echo -e "${BLUE}[INFO] 控制盒：自动检测${NC}"
                else
                  echo -e "${BLUE}[INFO] 控制盒：${USB_SELECT}${NC}"
                fi
                _run_ocs2_demo "${arm_label}真机" "${drag_flag}" "${type_arg}" "hardware:=real"
              fi
            fi
            ;;
          3)
            # Isaac：TopicBasedSystem ↔ /isaac/joint_*，无拖动模式
            echo -e "${BLUE}[INFO] Isaac：请先在 Isaac Sim Play，并确认 /isaac/joint_states 有数据${NC}"
            _run_ocs2_demo "${arm_label}Isaac" "false" "${type_arg}" "hardware:=isaac"
            ;;
          0)
            echo "返回"
            ;;
          *)
            echo -e "${YELLOW}无效选项${NC}"
            exit 1
            ;;
        esac
        ;;
      5)
        do_launch_joystick_teleop
        ;;
      0)
        echo "返回"
        ;;
      *)
        echo -e "${YELLOW}无效选项${NC}"
        exit 1
        ;;
    esac
    exit 0
fi

echo -e "${YELLOW}无效选项，请重新运行脚本${NC}"
exit 1
