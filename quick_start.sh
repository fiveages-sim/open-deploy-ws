#!/usr/bin/env bash

# 快速编译脚本（Deploy Workspace）
# - 自动识别当前 workspace 路径（脚本所在目录）
# - 仅负责编译通用包

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

WS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 缺少命令：$cmd${NC}"
    return 1
  fi
  return 0
}

need_cmd git || exit 1
need_cmd colcon || echo -e "${YELLOW}[WARN] 未找到 colcon，编译会失败（通常需要安装 ROS 发行版环境）。${NC}"

echo -e "${GREEN}开始编译...${NC}"
cd "${WS_DIR}" || exit 1
colcon build --packages-up-to \
  robot_common_launch \
  sensor_models \
  jodell_description \
  changingtek_description \
  linkerhand_description \
  robotiq_description \
  ocs2_arm_controller \
  basic_joint_controller \
  adaptive_gripper_controller \
  arms_controller_common \
  arms_teleop \
  arms_target_manager \
  arms_rviz_control_plugin \
  arms_ros2_control_msgs \
  lina_planning \
  ocs2_ros_interfaces \
  ocs2_mobile_manipulator_ros \
  ocs2_mobile_manipulator \
  ocs2_msgs \
  ocs2_self_collision_visualization \
  ocs2_self_collision \
  ocs2_pinocchio_interface \
  ocs2_robotic_tools \
  ocs2_mpc \
  ocs2_ddp \
  ocs2_qp_solver \
  ocs2_oc \
  ocs2_core \
  ocs2_thirdparty \
  ocs2_robotic_assets \
  topic_based_ros2_control \
  --symlink-install

if [ $? -eq 0 ]; then
  echo -e "${GREEN}编译完成！${NC}"
else
  echo -e "${YELLOW}编译过程中出现错误${NC}"
  exit 1
fi
