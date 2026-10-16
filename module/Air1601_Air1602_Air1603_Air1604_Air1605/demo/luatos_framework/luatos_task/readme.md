
## 演示功能概述

演示LuatOS运行框架如何使用，包括：

1、LuatOS task如何使用；

2、LuatOS msg如何使用；

3、LuatOS timer如何使用；

4、LuatOS 调度器如何使用；

5、以上四项功能全部基于sys核心库提供的api才能正常运行，所以本demo本质是在演示sys核心库提供的所有api如何使用；


## 演示硬件环境

参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

![](https://docs.openluat.com/air1601/luatos/common/download/image/download.jpg)

1、Air1601开发板一块

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；

- 在 Air1601 开发板上丝印标注 USB1，为芯片烧录下载接口；
- 若遇到因电脑 USB 端口供电不足导致的烧录失败，也可改用外部稳压电源通过开发板上的 VIN 引脚进行供电；

购买链接：[Air1601开发板 多功能5寸RGB屏 支持AirUI 摄像头 代开发固件-淘宝网](https://item.taobao.com/item.htm?id=1044228452703&pisk=g7HxDK_zIUYm-T9WJtAoI2UYUF-oHQm4wqoCIP4c143-zDKVIcagBV3tWrV6u-Dtycgp0lYqIbItY43T_nzg5P3ifjxkKpmq0Ry_BevHK46Wu23Aco1XfuZLv3qfMjIVRRy6-FClCSJLQq3lG8S1NuazXtZ_GVN7Vl47cONs5zN7Al6bCRg62_Z_vO_1ho97FzrT5Oa_17s7YkE1lRaX20azjRas5St-Vzr_CPG8aFU5cPXtNNVatv6IJO6seoFWZmaSFYKgcSHnDzLB-YpUMyibyOTj2W9QWzkBrQnrJjg04VppyJGEyAFQBKQUDbiLFr2B9_exqqkLhvLAnu2zoWG_wn9j2-UYwo0lc1ex1qkTgjIwY0wjzXzUGQ8z2xD36yPRPEio2rNK6qYPCrcKV4FnEaX3dXu-BWwC4_knpbbl-yEGG3KR_1Pb4Q1kC7_UChGa2yxvB15aa3r8-3KR_1Pb4uUHDhCN_7-P.&spm=a1z10.3-c-s.w4002-24045920836.13.3ff26ee5hNJu5K)


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air1601/luatos/common/download/)

2、内核固件文件（底层 core 固件文件）：本demo开发测试时使用的固件为[Air6101 V1016 版本固件](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；


## 演示核心步骤

1、搭建好硬件环境

2、在main.lua中按需启动如下某一段代码，单独演示某一项功能，这样分析起来比较清晰

``` lua
-- 加载“task调度”演示功能模块
-- require "scheduling"

-- 加载“task访问共享资源”演示功能模块
-- require "shared_resource"

-- 加载“查看用户可用ram信息”演示功能模块
-- require "memory_valid"

-- 加载“单个task占用的ram资源”演示功能模块
-- require "memory_task"

-- 加载“创建task的数量”演示功能模块
-- require "task_count"

-- 加载“task任务处理函数”演示功能模块
-- require "task_func"

-- 加载“task创建时的可变参数”演示功能模块
-- require "variable_args"

-- 加载“非目标消息回调函数”演示功能模块
-- require "non_targeted_msg"

-- 加载“用户全局消息处理”演示功能模块
-- require "global_msg_receiver1"
-- require "global_msg_receiver2"
-- require "global_msg_sender"

-- 加载“用户定向消息处理”演示功能模块
-- require "tgted_msg_receiver"
-- require "targeted_msg_sender"

-- 加载“定时器”演示功能模块
-- require "timer_func"

-- 加载“task内外部运行环境典型错误”演示功能模块
-- require "task_inout_env_err"
```

2、Luatools烧录内核固件和修改main.lua后的demo脚本代码

3、烧录成功后，自动开机运行

4、在main.lua中打开不同的演示功能模块，对应在Luatools的日志窗口会出现不同的日志信息，例如：

``` lua
[2026-05-19 15:48:31.292][LTOS/N][000000000.016]:I/user.main luatos_framework_luatos_task 001.999.000
[2026-05-19 15:48:31.295][LTOS/N][000000000.017]:I/user.task1_func 运行中，计数: 1
[2026-05-19 15:48:31.298][LTOS/N][000000000.018]:I/user.task_scheduling after task1 and before task2
[2026-05-19 15:48:31.302][LTOS/N][000000000.018]:I/user.task2_func 运行中，计数: 1
[2026-05-19 15:48:31.454][LTOS/N][000000000.318]:I/user.task2_func 运行中，计数: 2
[2026-05-19 15:48:31.640][LTOS/N][000000000.518]:I/user.task1_func 运行中，计数: 2
[2026-05-19 15:48:31.755][LTOS/N][000000000.619]:I/user.task2_func 运行中，计数: 3
[2026-05-19 15:48:32.041][LTOS/N][000000000.919]:I/user.task2_func 运行中，计数: 4
[2026-05-19 15:48:32.155][LTOS/N][000000001.018]:I/user.task1_func 运行中，计数: 3
[2026-05-19 15:48:32.355][LTOS/N][000000001.219]:I/user.task2_func 运行中，计数: 5
[2026-05-19 15:48:32.642][LTOS/N][000000001.518]:I/user.task1_func 运行中，计数: 4
[2026-05-19 15:48:32.651][LTOS/N][000000001.519]:I/user.task2_func 运行中，计数: 6
[2026-05-19 15:48:32.943][LTOS/N][000000001.820]:I/user.task2_func 运行中，计数: 7
[2026-05-19 15:48:33.142][LTOS/N][000000002.019]:I/user.task1_func 运行中，计数: 5
[2026-05-19 15:48:33.257][LTOS/N][000000002.120]:I/user.task2_func 运行中，计数: 8
[2026-05-19 15:48:33.555][LTOS/N][000000002.420]:I/user.task2_func 运行中，计数: 9
[2026-05-19 15:48:33.657][LTOS/N][000000002.519]:I/user.task1_func 运行中，计数: 6
[2026-05-19 15:48:33.858][LTOS/N][000000002.721]:I/user.task2_func 运行中，计数: 10
[2026-05-19 15:48:34.158][LTOS/N][000000003.019]:I/user.task1_func 运行中，计数: 7
[2026-05-19 15:48:34.162][LTOS/N][000000003.021]:I/user.task2_func 运行中，计数: 11
[2026-05-19 15:48:34.444][LTOS/N][000000003.321]:I/user.task2_func 运行中，计数: 12
[2026-05-19 15:48:34.643][LTOS/N][000000003.520]:I/user.task1_func 运行中，计数: 8
[2026-05-19 15:48:34.743][LTOS/N][000000003.621]:I/user.task2_func 运行中，计数: 13
[2026-05-19 15:48:35.058][LTOS/N][000000003.922]:I/user.task2_func 运行中，计数: 14
[2026-05-19 15:48:35.155][LTOS/N][000000004.020]:I/user.task1_func 运行中，计数: 9
[2026-05-19 15:48:35.360][LTOS/N][000000004.222]:I/user.task2_func 运行中，计数: 15
[2026-05-19 15:48:35.661][LTOS/N][000000004.520]:I/user.task1_func 运行中，计数: 10
[2026-05-19 15:48:35.673][LTOS/N][000000004.522]:I/user.task2_func 运行中，计数: 16
[2026-05-19 15:48:35.945][LTOS/N][000000004.823]:I/user.task2_func 运行中，计数: 17
[2026-05-19 15:48:36.161][LTOS/N][000000005.020]:I/user.task1_func 运行中，计数: 11
[2026-05-19 15:48:36.256][LTOS/N][000000005.123]:I/user.task2_func 运行中，计数: 18
[2026-05-19 15:48:36.546][LTOS/N][000000005.423]:I/user.task2_func 运行中，计数: 19
[2026-05-19 15:48:36.646][LTOS/N][000000005.521]:I/user.task1_func 运行中，计数: 12
[2026-05-19 15:48:36.862][LTOS/N][000000005.724]:I/user.task2_func 运行中，计数: 20
[2026-05-19 15:48:37.161][LTOS/N][000000006.021]:I/user.task1_func 运行中，计数: 13
[2026-05-19 15:48:37.163][LTOS/N][000000006.024]:I/user.task2_func 运行中，计数: 21
[2026-05-19 15:48:37.462][LTOS/N][000000006.324]:I/user.task2_func 运行中，计数: 22
[2026-05-19 15:48:37.662][LTOS/N][000000006.521]:I/user.task1_func 运行中，计数: 14
[2026-05-19 15:48:37.747][LTOS/N][000000006.624]:I/user.task2_func 运行中，计数: 23
```
