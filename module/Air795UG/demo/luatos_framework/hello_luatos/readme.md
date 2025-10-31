
## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔一秒钟通过日志输出一次Hello, LuatOS；


## 演示硬件环境

1、Air795UG开发板一块

2、TYPE-C USB数据线一根

4、Air795UG开发板和数据线的硬件接线方式为

- Air795UG开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/luatos/common/download/)

2、[Air795UG 最新版本的内核固件](https://docs.openluat.com/air795ug/luatos/firmware/version/)


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，每隔1秒输出1次Hello, LuatOS，就表示运行成功：

``` lua
[2025-10-31 11:08:34.979] I/user.Hello, LuatOS
[2025-10-31 11:08:35.817] I/user.Hello, LuatOS
[2025-10-31 11:08:36.912] I/user.Hello, LuatOS
[2025-10-31 11:08:37.821] I/user.Hello, LuatOS
[2025-10-31 11:08:38.988] I/user.Hello, LuatOS
[2025-10-31 11:08:39.853] I/user.Hello, LuatOS

```
