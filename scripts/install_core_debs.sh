#!/usr/bin/env bash
# 快速模式：从 GitHub Release 下载并安装 ocs2 / common / arms_ros2_control deb 包

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEB_CONF="${REPO_DIR}/deb_versions.conf"
ROS_DISTRO="${ROS_DISTRO:-jazzy}"
DEB_ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
DOWNLOAD_DIR="${REPO_DIR}/.deb_cache"

trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; echo "${v%"${v##*[![:space:]]}"}"; }

# 短名 → 包前缀（用于 --only）
resolve_only_token() {
  case "$1" in
    ocs2|ocs2_ros2|ros-jazzy-ocs2) echo "ros-jazzy-ocs2" ;;
    common|robot-descriptions-common|ros-jazzy-robot-descriptions-common) echo "ros-jazzy-robot-descriptions-common" ;;
    arms|arms_ros2_control|ros-jazzy-arms-ros2-control) echo "ros-jazzy-arms-ros2-control" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<EOF
用法: install_core_debs.sh [--ros-distro <distro>] [--config <file>] [--only <list>]

从 deb_versions.conf 读取仓库信息，按依赖顺序安装核心 deb 包：
  1. ros-jazzy-ocs2
  2. ros-jazzy-robot-descriptions-common
  3. ros-jazzy-arms-ros2-control（标准版，不含硬件驱动）

  --only <list>  仅安装指定包，逗号分隔。可用短名：ocs2, common, arms
                 示例: --only ocs2  或  --only ocs2,arms
                 未指定时安装配置文件中的全部包。
                 若指定 arms 且缺少本地依赖 common/ocs2，会自动补齐。

配置中 tag 留空或填 latest 时，自动从 GitHub 获取最新 release。
安装使用 apt-get install；核心包之间的依赖由本地 deb 满足（不在 apt 源中）。
EOF
}

ONLY_FILTER=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ros-distro) ROS_DISTRO="$2"; shift 2 ;;
    --config) DEB_CONF="$2"; shift 2 ;;
    --only)
      IFS=',' read -ra _only_tokens <<< "$2"
      for _tok in "${_only_tokens[@]}"; do
        _tok="$(trim "$_tok")"
        [[ -z "$_tok" ]] && continue
        if ! _resolved="$(resolve_only_token "$_tok")"; then
          print_error "未知 --only 项: $_tok（可用: ocs2, common, arms）"
          exit 1
        fi
        ONLY_FILTER+=("$_resolved")
      done
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) print_error "未知参数: $1"; usage; exit 1 ;;
  esac
done

should_install_prefix() {
  local prefix="$1" f
  if [[ ${#ONLY_FILTER[@]} -eq 0 ]]; then
    return 0
  fi
  for f in "${ONLY_FILTER[@]}"; do
    [[ "$f" == "$prefix" ]] && return 0
  done
  return 1
}

# 核心 deb 依赖（arms 硬依赖 common + ocs2，且二者不在 apt 源中）
core_deb_required_prefixes() {
  case "$1" in
    ros-jazzy-arms-ros2-control)
      printf '%s\n' "ros-jazzy-robot-descriptions-common" "ros-jazzy-ocs2"
      ;;
  esac
}

only_filter_contains() {
  local prefix="$1" f
  for f in "${ONLY_FILTER[@]}"; do
    [[ "$f" == "$prefix" ]] && return 0
  done
  return 1
}

# --only 自动补齐未安装的本地依赖，避免 apt「held broken packages」
expand_only_filter_with_deps() {
  local i=0 prefix dep
  [[ ${#ONLY_FILTER[@]} -eq 0 ]] && return 0

  while [[ "$i" -lt ${#ONLY_FILTER[@]} ]]; do
    prefix="${ONLY_FILTER[$i]}"
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      if only_filter_contains "$dep"; then
        continue
      fi
      if is_pkg_installed "$dep"; then
        print_info "依赖 ${dep} 已安装，跳过自动补齐"
        continue
      fi
      print_warn "安装 ${prefix} 需要本地 deb 依赖 ${dep}（不在 apt 源中），已自动加入安装列表"
      ONLY_FILTER+=("$dep")
    done < <(core_deb_required_prefixes "$prefix")
    i=$((i + 1))
  done
}

if [[ -z "$DEB_ARCH" ]]; then
  print_error "无法检测 dpkg 架构，请确认在 Debian/Ubuntu 环境中运行。"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  print_error "未找到 apt-get，请确认在 Debian/Ubuntu 环境中运行。"
  exit 1
fi

if [[ ! -f "$DEB_CONF" ]]; then
  print_error "未找到配置文件: $DEB_CONF"
  exit 1
fi

apt_run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get "$@"
  else
    sudo apt-get "$@"
  fi
}

is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# 按前缀匹配 release 中的 deb 资产（兼容新旧命名）
asset_patterns_for_prefix() {
  local prefix="$1"
  case "$prefix" in
    ros-jazzy-ocs2)
      printf '%s\n' \
        "${prefix}_*_${DEB_ARCH}.deb" \
        "*${prefix}*_${DEB_ARCH}.deb" \
        "ros-jazzy-ocs2-ros2-mobile-manipulator_*_${DEB_ARCH}.deb" \
        "*ocs2*jazzy*mobile-manipulator*_${DEB_ARCH}.deb" \
        "ocs2-ros2-jazzy-mobile-manipulator_*_${DEB_ARCH}.deb"
      ;;
    ros-jazzy-robot-descriptions-common)
      printf '%s\n' \
        "${prefix}_*_${DEB_ARCH}.deb" \
        "*${prefix}*_${DEB_ARCH}.deb" \
        "*robot-descriptions*jazzy*common*_${DEB_ARCH}.deb" \
        "robot-descriptions-jazzy-common_*_${DEB_ARCH}.deb"
      ;;
    ros-jazzy-arms-ros2-control)
      # 标准 WBC 包，不含 marvin/modbus 等硬件驱动（排除 *-full*）
      printf '%s\n' \
        "${prefix}_*_${DEB_ARCH}.deb"
      ;;
    *)
      printf '%s\n' \
        "${prefix}_*_${DEB_ARCH}.deb" \
        "*${prefix}*_${DEB_ARCH}.deb"
      ;;
  esac
}

should_exclude_deb_asset() {
  local prefix="$1" asset="$2"
  case "$prefix" in
    ros-jazzy-arms-ros2-control)
      [[ "$asset" == *"-full_"* || "$asset" == ros-jazzy-arms-ros2-control-full* ]] && return 0
      ;;
  esac
  return 1
}

glob_match() {
  local name="$1" pattern="$2"
  case "$name" in
    $pattern) return 0 ;;
    *) return 1 ;;
  esac
}

deb_file_size() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || wc -c < "$1"
}

fetch_release_assets_with_size() {
  local repo="$1" tag="$2"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}" \
    | python3 -c "
import json, sys
for a in json.load(sys.stdin).get('assets', []):
    print(str(a['name']) + '|' + str(a['size']))
" 2>/dev/null || true
}

lookup_asset_size() {
  local asset_name="$1"
  shift
  local line name size
  for line in "$@"; do
    name="${line%%|*}"
    size="${line#*|}"
    if [[ "$name" == "$asset_name" ]]; then
      printf '%s\n' "$size"
      return 0
    fi
  done
  return 1
}

is_valid_deb_file() {
  local deb_file="$1" expected_size="${2:-}"
  local actual_size=""

  [[ -f "$deb_file" ]] || return 1
  actual_size="$(deb_file_size "$deb_file")"
  [[ -n "$actual_size" && "$actual_size" -gt 0 ]] || return 1

  if [[ -n "$expected_size" && "$actual_size" -ne "$expected_size" ]]; then
    return 1
  fi

  ar t "$deb_file" >/dev/null 2>&1 || return 1
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -I "$deb_file" >/dev/null 2>&1 || return 1
  fi
  return 0
}

fetch_release_assets() {
  local repo="$1" tag="$2"
  fetch_release_assets_with_size "$repo" "$tag" | cut -d'|' -f1
}

release_exists() {
  local repo="$1" tag="$2"
  curl -fsSL -o /dev/null -w '%{http_code}' "https://api.github.com/repos/${repo}/releases/tags/${tag}" 2>/dev/null | grep -q '^200$'
}

fetch_latest_release_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases?per_page=20" \
    | python3 -c '
import json, sys
releases = json.load(sys.stdin)
for r in releases:
    if r.get("draft"):
        continue
    tag = r.get("tag_name", "")
    if tag:
        print(tag)
        break
' 2>/dev/null \
    || curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null \
    || true
}

resolve_release_tag() {
  local requested_tag="$1" primary_repo="$2" label="$3"
  local tag=""

  requested_tag="$(trim "$requested_tag")"
  primary_repo="$(trim "$primary_repo")"
  if [[ -z "$primary_repo" ]]; then
    print_error "${label}: 未配置 GitHub 仓库"
    return 1
  fi

  if [[ -n "$requested_tag" && "$requested_tag" != "latest" && "$requested_tag" != "*" ]]; then
    if [[ "$requested_tag" != [vV]* ]]; then
      requested_tag="v${requested_tag}"
    fi
    printf '%s\n' "$requested_tag"
    return 0
  fi

  tag="$(fetch_latest_release_tag "$primary_repo")"
  if [[ -n "$tag" ]]; then
    print_info "  ${label}: 使用 ${primary_repo} 最新 release ${tag}"
    printf '%s\n' "$tag"
    return 0
  fi

  print_error "无法解析 ${label} 的最新 release tag（仓库: ${primary_repo}）"
  return 1
}

download_file_with_progress() {
  local url="$1" dest="$2" filename="$3"
  print_info "  下载 ${filename} ..."
  print_info "  来源: ${url}"

  # --progress-bar 输出到 stderr，不干扰命令替换；大文件显示下载进度
  if curl -fL --progress-bar --connect-timeout 30 --retry 3 --retry-delay 2 \
      -o "$dest" "$url"; then
    local size
    size="$(du -h "$dest" | awk '{print $1}')"
    print_info "  下载完成 (${size}): ${dest}"
    return 0
  fi
  return 1
}

purge_stale_deb_cache() {
  local prefix="$1" keep_file="$2"
  local f bn

  [[ -d "$DOWNLOAD_DIR" ]] || return 0

  shopt -s nullglob
  for f in "${DOWNLOAD_DIR}/${prefix}"_*.deb "${DOWNLOAD_DIR}/${prefix}"_*.deb.part; do
    bn="$(basename "$f")"
    [[ "$bn" == "$keep_file" || "$bn" == "${keep_file}.part" ]] && continue
    print_info "  清除旧版本缓存: ${bn}"
    rm -f "$f"
  done
  shopt -u nullglob
}

download_deb_for_package() {
  local prefix="$1" tag="$2" primary_repo="$3"
  local repo asset patterns=() matched="" url dest tmp_dest resolved_tag expected_size=""
  local -a asset_lines=()

  primary_repo="$(trim "$primary_repo")"
  resolved_tag="$(resolve_release_tag "$tag" "$primary_repo" "$prefix")" || return 1
  tag="$resolved_tag"

  if ! release_exists "$primary_repo" "$tag"; then
    print_error "  ${primary_repo}@${tag} 不存在"
    return 1
  fi

  mapfile -t asset_lines < <(fetch_release_assets_with_size "$primary_repo" "$tag")
  if [[ ${#asset_lines[@]} -eq 0 ]]; then
    print_error "  ${primary_repo}@${tag} 无 release 资产"
    return 1
  fi

  matched=""
  mapfile -t patterns < <(asset_patterns_for_prefix "$prefix")
  for pattern in "${patterns[@]}"; do
    for asset in "${asset_lines[@]}"; do
      asset="${asset%%|*}"
      should_exclude_deb_asset "$prefix" "$asset" && continue
      if glob_match "$asset" "$pattern"; then
        matched="$asset"
        break 2
      fi
    done
  done

  if [[ -z "$matched" ]]; then
    print_error "  ${primary_repo}@${tag} 未找到匹配 ${prefix} 的 deb（架构 ${DEB_ARCH}）"
    print_warn "  可用资产: $(printf '%s\n' "${asset_lines[@]}" | cut -d'|' -f1 | tr '\n' ' ')"
    return 1
  fi

  expected_size="$(lookup_asset_size "$matched" "${asset_lines[@]}")" || expected_size=""

  mkdir -p "$DOWNLOAD_DIR"
  dest="${DOWNLOAD_DIR}/${matched}"
  tmp_dest="${dest}.part"

  purge_stale_deb_cache "$prefix" "$matched"

  if [[ -f "$dest" ]]; then
    if is_valid_deb_file "$dest" "$expected_size"; then
      print_info "  已缓存: $dest"
      printf '%s\n' "$dest"
      return 0
    fi
    print_warn "  缓存文件不完整或已损坏（期望 ${expected_size:-未知} 字节），将重新下载..."
    rm -f "$dest" "${dest}.part"
  fi

  url="https://github.com/${primary_repo}/releases/download/${tag}/${matched}"
  rm -f "$tmp_dest"
  if download_file_with_progress "$url" "$tmp_dest" "$matched"; then
    if is_valid_deb_file "$tmp_dest" "$expected_size"; then
      mv -f "$tmp_dest" "$dest"
      printf '%s\n' "$dest"
      return 0
    fi
    print_error "  下载完成但文件校验失败（可能网络中断），请重试"
  fi
  rm -f "$tmp_dest"
  print_error "  下载失败: $url"
  return 1
}

diagnose_install_failure() {
  local deb_file="$1" log_file="$2"
  local pkg missing_deps=() line dep

  pkg="$(dpkg-deb -f "$deb_file" Package 2>/dev/null || true)"
  [[ -z "$pkg" ]] && pkg="$(basename "$deb_file")"

  if grep -qE 'held broken packages|unmet dependencies|is not installable|Depends:' "$log_file"; then
    print_error "apt 依赖无法满足（通常不是 deb 缓存损坏）"
    while IFS= read -r line; do
      print_error "  ${line}"
    done < <(grep -E 'Depends:|but it is not|held broken|unmet dependencies|packages have unmet' "$log_file" | sed 's/^[[:space:]]*//' | uniq)

    if [[ -n "$pkg" ]]; then
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        is_pkg_installed "$dep" || missing_deps+=("$dep")
      done < <(core_deb_required_prefixes "$pkg")
    fi
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
      print_error "缺少需从 GitHub Release 安装的本地依赖: ${missing_deps[*]}"
      print_info "请重新运行安装（脚本会自动补齐），或手动: scripts/install_core_debs.sh --only ocs2,common,arms"
    fi
    return 0
  fi
  return 1
}

install_deb() {
  local deb_file="$1"
  local log_file rc=0

  print_info "安装 ${deb_file} ..."
  log_file="$(mktemp)"
  # apt 进度仍输出到终端；同时保留日志用于诊断
  apt_run install -y "$deb_file" 2>&1 | tee "$log_file"
  rc=${PIPESTATUS[0]}

  if [[ "$rc" -eq 0 ]]; then
    rm -f "$log_file"
    return 0
  fi

  if diagnose_install_failure "$deb_file" "$log_file"; then
    print_warn "保留 deb 缓存以便修复依赖后重试: ${deb_file}"
    rm -f "$log_file"
    return 1
  fi

  if ! is_valid_deb_file "$deb_file"; then
    print_warn "安装失败且 deb 校验失败，删除可能损坏的缓存: ${deb_file}"
    rm -f "$deb_file" "${deb_file}.part"
  else
    print_error "安装失败（已保留有效缓存）: ${deb_file}"
    print_error "请检查上方 apt 输出；若为权限/锁问题，关闭其他 apt 进程后重试"
  fi
  rm -f "$log_file"
  return 1
}

# 读取配置（文件顺序即安装顺序：ocs2 → common → arms）
DEB_SPECS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(trim "$line")"
  [[ -z "$line" ]] && continue
  DEB_SPECS+=("$line")
done < "$DEB_CONF"

if [[ ${#DEB_SPECS[@]} -eq 0 ]]; then
  print_error "deb_versions.conf 中没有有效条目"
  exit 1
fi

print_info "安装核心 deb 包（ROS ${ROS_DISTRO}，架构 ${DEB_ARCH}）"
print_info "安装顺序: ocs2 → common → arms_ros2_control"
print_info "配置文件: $DEB_CONF"
expand_only_filter_with_deps
if [[ ${#ONLY_FILTER[@]} -gt 0 ]]; then
  print_info "仅安装: ${ONLY_FILTER[*]}"
fi
echo "" >&2

installed=()
step=0
total_to_install=0
for spec in "${DEB_SPECS[@]}"; do
  IFS='|' read -r prefix _tag _repo <<< "$spec"
  prefix="$(trim "$prefix")"
  should_install_prefix "$prefix" && total_to_install=$((total_to_install + 1))
done
if [[ "$total_to_install" -eq 0 ]]; then
  print_error "没有匹配 --only 的包可安装"
  exit 1
fi

for spec in "${DEB_SPECS[@]}"; do
  IFS='|' read -r prefix tag primary_repo <<< "$spec"
  prefix="$(trim "$prefix")"
  tag="$(trim "$tag")"
  primary_repo="$(trim "$primary_repo")"

  if ! should_install_prefix "$prefix"; then
    continue
  fi

  step=$((step + 1))
  print_info "[${step}/${total_to_install}] 处理 ${prefix} ..."
  deb_path="$(download_deb_for_package "$prefix" "$tag" "$primary_repo")" || exit 1
  install_deb "$deb_path" || {
    print_error "安装 ${prefix} 失败"
    exit 1
  }
  installed+=("$prefix")
  echo "" >&2
done

print_info "=========================================="
print_info "核心 deb 包安装完成："
for pkg in "${installed[@]}"; do
  print_info "  ✓ ${pkg}"
done
print_info "=========================================="
print_info ""
print_info "使用前请 source ROS 环境："
print_info "  source /opt/ros/${ROS_DISTRO}/setup.bash"
