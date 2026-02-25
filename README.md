# open-deploy-ws

ROS2 部署工作空间，集成双臂机械臂控制、机器人描述模型与 OCS2 MPC 框架。

## 工作空间结构

```
open-deploy-ws/
├── src/
│   ├── arms_ros2_control/          # 机械臂控制核心（子模块）
│   │   ├── controller/
│   │   │   ├── ocs2_arm_controller/          # OCS2 MPC 臂控制器
│   │   │   ├── basic_joint_controller/       # 基础关节控制器
│   │   │   └── adaptive_gripper_controller/  # 自适应夹爪控制器
│   │   ├── command/
│   │   │   ├── arms_ros2_control_msgs/       # 控制消息定义
│   │   │   ├── arms_rviz_control_plugin/     # RViz 控制面板插件
│   │   │   ├── arms_target_manager/          # 末端目标管理（3D 交互标记）
│   │   │   └── arms_teleop/                  # 统一遥操作（手柄/键盘）
│   │   ├── hardwares/
│   │   │   ├── topic_based_ros2_control/     # Topic 硬件接口（含 Isaac Sim 支持）
│   │   │   ├── gz_ros2_control/              # Gazebo 硬件接口
│   │   │   ├── unitree_ros2_control/         # Unitree 机器人硬件接口
│   │   │   └── ...                           # 其他厂商硬件接口
│   │   └── libraries/
│   │       ├── arms_controller_common/       # 控制器公共库
│   │       └── lina_planning/                # 规划库（嵌套子模块）
│   ├── robot-descriptions/         # 机器人描述文件（子模块）
│   │   ├── common/                           # 公共组件（嵌套子模块）
│   │   │   ├── robot_common_launch/          # 通用 launch 文件
│   │   │   ├── sensor_models/                # 传感器模型
│   │   │   ├── gripper/                      # 夹爪描述（jodell / changingtek / linkerhand / robotiq）
│   │   │   └── dexhands/                     # 灵巧手描述
│   │   ├── manipulator/                      # 机械臂描述
│   │   └── humanoid/                         # 人形机器人描述
│   └── ocs2_ros2/                  # OCS2 MPC 框架（子模块）
│       └── submodules/
│           └── ocs2_robotic_assets/          # OCS2 机器人资产（嵌套子模块）
├── init_repo.sh                    # 一键初始化 + 编译脚本
└── README.md
```

## 快速开始

```bash
git clone git@github.com:fiveages-sim/open-deploy-ws.git ros2_ws
cd ros2_ws
./init_repo.sh
```

**`init_repo.sh` 完成以下工作：**
1. 同步并初始化顶层子模块（`arms_ros2_control`、`ocs2_ros2`、`robot-descriptions`）
2. 初始化编译所需的嵌套子模块（`robot-descriptions/common`、`lina_planning`、`ocs2_robotic_assets`）
3. 将所有子模块切换到配置的分支并拉取最新提交
4. 运行 `rosdep install` 安装系统依赖
5. 运行 `colcon build` 编译所有核心包


## 测试环境

- **ROS2 Jazzy**（Ubuntu 24.04）


## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
