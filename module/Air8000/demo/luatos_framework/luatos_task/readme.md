
## 演示功能概述

1、创建一个task；

2、在task中的任务处理函数中，每隔一秒钟通过日志输出一次Hello, LuatOS；


## 演示硬件环境

1、Air8000核心板一块

2、TYPE-C USB数据线一根

4、Air8101核心板和数据线的硬件接线方式为

- Air8101核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 供电/充电 拨动开关 拨到供电一端；
- 核心板背面的 USB ON/USB OFF 拨动开关 拨到USB ON一端；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

2、[Air8000 最新版本的内核固件](https://docs.openluat.com/air8000/luatos/firmware/)


## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行

4、出现类似于下面的日志，每隔1秒输出1次Hello, LuatOS，就表示运行成功：

``` lua
[2025-07-19 23:19:04.944][000000015.256] I/user.Hello, LuatOS
[2025-07-19 23:19:05.954][000000016.256] I/user.Hello, LuatOS
[2025-07-19 23:19:06.956][000000017.256] I/user.Hello, LuatOS
[2025-07-19 23:19:07.947][000000018.256] I/user.Hello, LuatOS
[2025-07-19 23:19:08.955][000000019.256] I/user.Hello, LuatOS
[2025-07-19 23:19:09.944][000000020.256] I/user.Hello, LuatOS

```
