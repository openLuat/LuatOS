
## 演示功能概述

演示LuatOS运行框架如何使用，包括：

1、LuatOS task如何使用；

2、LuatOS msg如何使用；

3、LuatOS timer如何使用；

4、LuatOS 调度器如何使用；

5、以上四项功能全部基于sys核心库提供的api才能正常运行，所以本demo本质是在演示sys核心库提供的所有api如何使用；


## 演示硬件环境

1、Air780EXX核心板一块

2、TYPE-C USB数据线一根

4、Air780EXX核心板和数据线的硬件接线方式为

- Air780EXX核心板通过TYPE-C USB口连接TYPE-C USB 数据线，数据线的另外一端连接电脑的USB口；
- 核心板正面的 ON/OFF 拨动开关 拨到ON一端；


## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780ehv/luatos/common/download/)

2、[Air780EHM 最新版本的内核固件](https://docs.openluat.com/air780epm/luatos/firmware/version/)

3、[Air780EHV 最新版本的内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)

4、[Air780EGH 最新版本的内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)


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
-- require "timer"

-- 加载“task内外部运行环境典型错误”演示功能模块
-- require "task_inout_env_err"
```

2、Luatools烧录内核固件和修改main.lua后的demo脚本代码

3、烧录成功后，自动开机运行

4、在main.lua中打开不同的演示功能模块，对应在Luatools的日志窗口会出现不同的日志信息，例如：

``` lua
如果在main.lua中开启以下代码
-- 加载“task调度”演示功能模块
require "scheduling"

则日志信息如下：
[2025-08-28 12:04:33.469][00000000.228] I/user.task1_func 运行中，计数: 1
[2025-08-28 12:04:33.469][00000000.228] I/user.task_scheduling after task1 and before task2
[2025-08-28 12:04:33.469][00000000.228] I/user.task2_func 运行中，计数: 1
[2025-08-28 12:04:33.554][00000000.313] I/user.task2_func 运行中，计数: 2
[2025-08-28 12:04:33.748][00000000.507] I/user.task1_func 运行中，计数: 2
[2025-08-28 12:04:33.865][00000000.624] I/user.task2_func 运行中，计数: 3
[2025-08-28 12:04:34.179][00000000.938] I/user.task2_func 运行中，计数: 4
[2025-08-28 12:04:34.254][00000001.013] I/user.task1_func 运行中，计数: 3
[2025-08-28 12:04:34.494][00000001.253] I/user.task2_func 运行中，计数: 5
[2025-08-28 12:04:34.763][00000001.522] I/user.task1_func 运行中，计数: 4
[2025-08-28 12:04:34.808][00000001.567] I/user.task2_func 运行中，计数: 6
[2025-08-28 12:04:35.121][00000001.880] I/user.task2_func 运行中，计数: 7
[2025-08-28 12:04:35.274][00000002.033] I/user.task1_func 运行中，计数: 5
[2025-08-28 12:04:35.436][00000002.196] I/user.task2_func 运行中，计数: 8
[2025-08-28 12:04:35.739][00000002.499] I/user.task2_func 运行中，计数: 9
[2025-08-28 12:04:35.783][00000002.542] I/user.task1_func 运行中，计数: 6
[2025-08-28 12:04:36.046][00000002.806] I/user.task2_func 运行中，计数: 10
[2025-08-28 12:04:36.285][00000003.045] I/user.task1_func 运行中，计数: 7
[2025-08-28 12:04:36.357][00000003.116] I/user.task2_func 运行中，计数: 11
[2025-08-28 12:04:36.661][00000003.420] I/user.task2_func 运行中，计数: 12
[2025-08-28 12:04:36.797][00000003.556] I/user.task1_func 运行中，计数: 8
[2025-08-28 12:04:36.960][00000003.719] I/user.task2_func 运行中，计数: 13
[2025-08-28 12:04:37.275][00000004.034] I/user.task2_func 运行中，计数: 14
[2025-08-28 12:04:37.305][00000004.064] I/user.task1_func 运行中，计数: 9
[2025-08-28 12:04:37.579][00000004.338] I/user.task2_func 运行中，计数: 15
[2025-08-28 12:04:37.818][00000004.577] I/user.task1_func 运行中，计数: 10
[2025-08-28 12:04:37.889][00000004.648] I/user.task2_func 运行中，计数: 16
[2025-08-28 12:04:38.199][00000004.958] I/user.task2_func 运行中，计数: 17
[2025-08-28 12:04:38.325][00000005.084] I/user.task1_func 运行中，计数: 11
[2025-08-28 12:04:38.500][00000005.259] I/user.task2_func 运行中，计数: 18
[2025-08-28 12:04:38.812][00000005.571] I/user.task2_func 运行中，计数: 19
[2025-08-28 12:04:38.825][00000005.584] I/user.task1_func 运行中，计数: 12
[2025-08-28 12:04:39.113][00000005.872] I/user.task2_func 运行中，计数: 20
[2025-08-28 12:04:39.333][00000006.092] I/user.task1_func 运行中，计数: 13
[2025-08-28 12:04:39.414][00000006.173] I/user.task2_func 运行中，计数: 21
[2025-08-28 12:04:39.717][00000006.476] I/user.task2_func 运行中，计数: 22
[2025-08-28 12:04:39.835][00000006.594] I/user.task1_func 运行中，计数: 14
[2025-08-28 12:04:40.020][00000006.779] I/user.task2_func 运行中，计数: 23

```
