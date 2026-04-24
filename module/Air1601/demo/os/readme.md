## **功能模块介绍**

本项目是Luatos os核心库的完整功能演示，严格按照官方API文档实现，展示了os库中所有标准接口的使用方法。通过本演示项目，开发者可以快速掌握LuatOS中os核心库功能的使用。

1、main.lua：主程序入口 <br> 
2、os_core_demo.lua：os核心库API演示模块，严格按照官方文档实现os.date、os.time、os.difftime、os.remove、os.rename五个标准接口的顺序演示功能。<br> 

## **演示功能概述**

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号
- 初始化看门狗，并定时喂狗
- 启动一个循环定时器，每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况方便分析内存使用是否有异常
- 加载os_core_demo模块（通过require "os_core_demo"）
- 最后运行sys.run()。

### 2、os核心库API演示模块（os_core_demo.lua）

#### 时间日期处理
- **os.date()** - 格式化时间日期，支持strftime格式规范
- **os.time()** - 获取Unix时间戳，支持自定义时间表
- **os.difftime()** - 计算两个时间戳的差值

#### 文件操作功能
- **os.remove()** - 删除指定路径的文件
- **os.rename()** - 重命名文件或移动文件

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

## **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：

本demo开发测试时使用的固件为[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/)，本demo对固件版本没有什么特殊要求，所以你如果要测试本demo时，可以直接使用最新版本的内核固件；如果发现最新版本的内核固件测试有问题，可以使用我们开发本demo时使用的内核固件版本来对比测试。

## **演示核心步骤**

1、搭建好硬件环境

2、通过Luatools将demo与固件烧录到开发板中

3、烧录好后，板子开机将会在Luatools上看到如下打印

```lua
[2025-10-23 16:47:38.274][00000000.043] I/user.os_core ===== 开始os核心库API演示 =====
[2025-10-23 16:47:38.274][00000000.043] I/user.os.date ===== 开始os.date接口演示 =====
[2025-10-23 16:47:38.274][00000000.043] I/user.os.date 默认格式本地时间: Thu Oct 23 16:47:38 2025
[2025-10-23 16:47:38.274][00000000.044] I/user.os.date 自定义格式本地时间: 2025-10-23 16:47:38
[2025-10-23 16:47:38.274][00000000.044] I/user.os.date UTC时间: 2025-10-23 08:47:38
[2025-10-23 16:47:38.275][00000000.044] I/user.os.date 本地时间table: year=2025, month=10, day=23
[2025-10-23 16:47:38.275][00000000.044] I/user.os.date UTC时间table: year=2025, month=10, day=23
[2025-10-23 16:47:38.275][00000000.044] I/user.os.date 指定时间戳格式化: 2024年12月25日 10:30:00
[2025-10-23 16:47:38.275][00000000.044] I/user.os.date ===== os.date接口演示完成 =====
[2025-10-23 16:47:38.275][00000000.044] I/user.os.time ===== 开始os.time接口演示 =====
[2025-10-23 16:47:38.275][00000000.044] I/user.os.time 当前时间戳: 1761209258 秒
[2025-10-23 16:47:38.275][00000000.044] I/user.os.time 指定时间的时间戳: 1735093800 秒
[2025-10-23 16:47:38.275][00000000.045] I/user.os.time 当前时间详细信息: year=2025, month=10, day=23
[2025-10-23 16:47:38.276][00000000.045] I/user.os.time ===== os.time接口演示完成 =====
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime ===== 开始os.difftime接口演示 =====
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime 时间点A (2024-01-01): 1704038400 秒
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime 时间点B (2025-01-01): 1735660800 秒
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime 时间差(B-A): 3.162240e+07 秒
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime 时间差(B-A): 366.000 天
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime 时间差(A-B): -3.162240e+07 秒
[2025-10-23 16:47:38.276][00000000.045] I/user.os.difftime ===== os.difftime接口演示完成 =====
[2025-10-23 16:47:38.276][00000000.045] I/user.os.remove ===== 开始os.remove接口演示 =====
[2025-10-23 16:47:38.276][00000000.046] D/fs fopen os_test_delete.txt wb
[2025-10-23 16:47:38.278][00000000.047] I/user.os.remove 创建测试文件成功: /os_test_delete.txt
[2025-10-23 16:47:38.278][00000000.047] D/fs fopen os_test_delete.txt rb
[2025-10-23 16:47:38.279][00000000.048] I/user.os.remove 测试文件存在，准备删除
[2025-10-23 16:47:38.281][00000000.051] I/user.os.remove 文件删除成功
[2025-10-23 16:47:38.281][00000000.051] D/fs fopen os_test_delete.txt rb
[2025-10-23 16:47:38.282][00000000.051] D/vfs fopen /os_test_delete.txt r not found
[2025-10-23 16:47:38.282][00000000.051] I/user.os.remove 删除验证通过，文件已不存在
[2025-10-23 16:47:38.282][00000000.051] I/user.os.remove ===== os.remove接口演示完成 =====
[2025-10-23 16:47:38.282][00000000.052] I/user.os.rename ===== 开始os.rename接口演示 =====
[2025-10-23 16:47:38.282][00000000.052] D/fs fopen os_test_old.txt wb
[2025-10-23 16:47:38.284][00000000.054] I/user.os.rename 创建源文件成功: /os_test_old.txt
[2025-10-23 16:47:38.285][00000000.054] D/fs fopen os_test_old.txt rb
[2025-10-23 16:47:38.285][00000000.054] I/user.os.rename 源文件存在，准备重命名
[2025-10-23 16:47:38.285][00000000.054] D/fs fopen os_test_new.txt rb
[2025-10-23 16:47:38.286][00000000.055] D/vfs fopen /os_test_new.txt r not found
[2025-10-23 16:47:38.289][00000000.058] I/user.os.rename 文件重命名成功: /os_test_old.txt -> /os_test_new.txt
[2025-10-23 16:47:38.289][00000000.058] D/fs fopen os_test_old.txt rb
[2025-10-23 16:47:38.289][00000000.059] D/vfs fopen /os_test_old.txt r not found
[2025-10-23 16:47:38.290][00000000.059] I/user.os.rename 原文件已不存在，重命名验证通过
[2025-10-23 16:47:38.290][00000000.059] D/fs fopen os_test_new.txt rb
[2025-10-23 16:47:38.290][00000000.060] I/user.os.rename 新文件存在验证通过: /os_test_new.txt
[2025-10-23 16:47:38.294][00000000.063] I/user.os.rename 测试文件已清理
[2025-10-23 16:47:38.294][00000000.064] I/user.os.rename ===== os.rename接口演示完成 =====
[2025-10-23 16:47:38.295][00000000.064] I/user.os_core ===== os核心库API演示全部完成 =====
```