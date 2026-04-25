# AUBO Runtime Files

这个目录不是 ROS 包，而是 `aubo_ros2_control` 运行时依赖的最小 AUBO 文件集合。

当前保留的文件只有：

```text
include/
  serviceinterface.h
  AuboRobotMetaType.h
  robotiomatetype.h

lib/
  libauborobotcontroller.so.1.3.2
  liblog4cplus-1.2.so.5
```

说明：

- `include/` 里的头文件用于编译 `aubo_ros2_control`
- `libauborobotcontroller.so.1.3.2` 是 AUBO 官方 SDK 主库
- `liblog4cplus-1.2.so.5` 是 AUBO 主库的运行时依赖

如果只做 AUBO 仿真联调，不会真正访问控制柜；但只要重新编译 `aubo_ros2_control`，这里的头文件和动态库仍然需要存在。
