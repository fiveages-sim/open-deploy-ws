# open-deploy-ws

ROS2 部署工作空间，集成双臂机械臂控制、机器人描述模型与 OCS2 MPC 框架。

## 关于其他分支

`main` 面向完整 / 通用部署工作空间。仓库中还有面向特定机型的精简分支，**只拉取该方案所需的包与子模块**，以减小克隆与部署体积：

- **`dobot-cr5`**：Dobot CR5 部署工作空间，仅包含 CR5 相关描述、驱动与控制依赖
- **`arx-acone`**：ARX Acone 部署工作空间，仅包含 Acone 相关描述、驱动与控制依赖

使用时在克隆时指定分支，建议目录名与机型对应，例如：

```bash
git clone -b dobot-cr5 git@github.com:fiveages-sim/open-deploy-ws.git dobot_cr5_ws
git clone -b arx-acone git@github.com:fiveages-sim/open-deploy-ws.git arx_acone_ws
```

## 工作空间结构

```
open-deploy-ws/
├── src/
│   ├── arms_ros2_control/     # 机械臂控制核心（控制器 / 命令 / 硬件接口 / 公共库）
│   ├── robot-descriptions/    # 机器人描述（common / manipulator / humanoid）
│   └── ocs2_ros2/             # OCS2 MPC 框架
├── init_repo.sh               # 一键初始化（可见性 + 逐模块 source/deb）
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
git clone https://github.com/fiveages-sim/open-deploy-ws.git ros2_ws
# 已配置 SSH 密钥时也可以：
# git clone git@github.com:fiveages-sim/open-deploy-ws.git ros2_ws
cd ros2_ws
./init_repo.sh
```

容器或 CI（无法按回车）请用非交互参数，默认与交互菜单一致：

```bash
./init_repo.sh --public --ocs2=deb --arms=source --common=source
```

### `init_repo.sh` 操作说明

**1) 初始化工作空间（推荐）**

分两步选择：

1. **嵌套可见性**（只影响各仓库内部的嵌套子模块；顶层三个仓在选 source 时都会初始化）
   - **public**：仅公开嵌套，适用于外部用户
   - **private**：含私有嵌套，需要内部仓库权限
2. **核心模块安装方式**（逐项 `d`=deb / `s`=source，回车用默认）

| 模块 | 路径 | deb 包 | 默认 |
|------|------|--------|------|
| ocs2 | `src/ocs2_ros2` | `ros-jazzy-ocs2` | **deb** |
| arms | `src/arms_ros2_control` | `ros-jazzy-arms-ros2-control` | source |
| common | `src/robot-descriptions/common` | `ros-jazzy-robot-descriptions-common` | source |

推荐业务组合（脚本默认）：**ocs2=deb，arms/common=source**。全源码即三模块都选 `s`；全 deb 即三模块都选 `d`。

**2) 切换模块安装方式**

探测当前 dpkg / 源码目录状态，按模块在 source ↔ deb 之间切换（会清理冲突源码或卸载对应 deb），然后按目标重新同步。

**3) 仅安装/更新核心 deb**

跳过 Git 拉取；可输入 `ocs2`、`common`、`arms`（逗号分隔），回车表示全部。也可直接运行：

```bash
./scripts/install_core_debs.sh --only ocs2
```

**4) 卸载核心 deb**

可指定包或全部；也可运行 `./scripts/uninstall_core_debs.sh --only ocs2`。

**5) 仅运行 rosdep**

对整个 `src` 安装系统依赖（不拉取子模块、不装 deb）：

```bash
rosdep install --from-paths src --ignore-src -r -y
```

deb 版本与仓库见 [`deb_versions.conf`](deb_versions.conf)；嵌套 public/private 见 [`submodules_visibility.conf`](submodules_visibility.conf)。

### 非交互参数与环境变量

`./init_repo.sh --help` 可查看完整列表。常用项：

| 参数 | 环境变量 | 含义 |
|------|----------|------|
| `--public` / `--private` | `OPEN_DEPLOY_VISIBILITY` | 嵌套可见性 |
| `--ocs2=deb\|source` | `OPEN_DEPLOY_OCS2` | ocs2 安装方式 |
| `--arms=deb\|source` | `OPEN_DEPLOY_ARMS` | arms 安装方式 |
| `--common=deb\|source` | `OPEN_DEPLOY_COMMON` | common 安装方式 |
| `--https` | `OPEN_DEPLOY_GIT_HTTPS=1` | 强制 HTTPS 拉取 GitHub 子模块 |
| `-y` / `--yes` | `OPEN_DEPLOY_YES=1` | 自动确认清理源码目录 |

传入 `--public`、`--private` 或任一模块参数即进入非交互模式，不再等待键盘输入。

### SSH 与 HTTPS

`.gitmodules`（以及 arms / robot-descriptions 的嵌套 `.gitmodules`）使用 `git@github.com:`。在没有 `ssh` 二进制、或 public 模式且没有可用 SSH 密钥的环境中，`git submodule update` 会报 `error: cannot run ssh: No such file or directory`。

**仅设置** `git config url.https://github.com/.insteadOf git@github.com:` **不能可靠修好** 子模块更新：嵌套仓会读自己的 `.gitmodules`，并直接走 ssh。本脚本会在需要时把 GitHub SSH URL **改写为 HTTPS**，再 `submodule sync` / `update`，结束后还原 `.gitmodules`，避免把 URL 变更写进工作区。已有 SSH 密钥的用户（尤其是 private 嵌套）保持原 SSH URL。也可显式传 `--https`。

### 脚本随后会

1. 同步并初始化选为 **source** 的顶层子模块（选 deb 的跳过；若已有源码会提示清理）
2. 按可见性与配置初始化嵌套子模块（父仓或 common 为 deb 时跳过）
3. public 模式下对未初始化的空 private / hardware 嵌套目录写入 `COLCON_IGNORE`，避免 colcon 扫描空目录
4. 将源码子模块切换到配置分支并拉取最新提交
5. 对源码路径运行 `rosdep install`
6. 安装选为 deb 的包（顺序：ocs2 → common → arms）
7. 将选择写入本地 `.core_module_mode`（已 gitignore），供下次默认参考

## 测试环境

- **ROS2 Jazzy**（Ubuntu 24.04）


## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
