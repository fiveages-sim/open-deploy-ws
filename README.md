# open-deploy-ws

ROS2 部署工作空间，集成双臂机械臂控制、机器人描述模型与 OCS2 MPC 框架。

## 工作空间结构

```
open-deploy-ws/
├── src/
│   ├── arms_ros2_control/     # 机械臂控制核心（控制器 / 命令 / 硬件接口 / 公共库）
│   ├── robot-descriptions/    # 机器人描述（common / manipulator / humanoid）
│   └── ocs2_ros2/             # OCS2 MPC 框架
├── init_repo.sh               # 一键初始化 + 编译
└── README.md
```

## 快速开始

在开始前，请先完成 **ROS 2 Jazzy 及 rosdep 环境** 安装（Ubuntu 24.04）：

```bash
# 1. 安装 ROS 2 管理工具（fishros）
wget http://fishros.com/install -O fishros && bash fishros

# 2. 安装 ROS 2 Jazzy 桌面版
sudo apt update
sudo apt install ros-jazzy-desktop

# 3. 初始化 rosdep（首次在本机使用 rosdep 时需要）
sudo rosdep init
rosdep update
```

完成以上步骤后，再执行仓库初始化：

```bash
git clone git@github.com:fiveages-sim/open-deploy-ws.git ros2_ws
cd ros2_ws
./init_repo.sh
```

**运行 `init_repo.sh` 时可选择初始化模式：**
- **public**（默认，直接回车即选）：仅初始化公开子模块，适用于外部用户，无需私有仓库权限。
- **private**：初始化所有子模块（含私有仓库），需要具备内部仓库访问权限。

**脚本随后会：**
1. 同步并初始化顶层子模块
2. 根据所选模式与 `submodules_visibility.conf` 初始化嵌套子模块
3. 将所有子模块切换到配置的分支并拉取最新提交
4. 运行 `rosdep install` 安装系统依赖
5. 运行 `colcon build` 编译所有核心包


## 测试环境

- **ROS2 Jazzy**（Ubuntu 24.04）


## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
