## **功能模块介绍**

本项目是LuatOS os核心库的完整功能演示，严格按照官方API文档实现，展示了OS库中所有标准接口的使用方法。通过本演示项目，开发者可以快速掌握LuatOS中os核心库功能的使用。

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


## **演示硬件环境**

1、Air780EHM核心板一块(Air780EHM/780EGH/780EHV三种模块的核心板接线方式相同，这里以Air780EHM为例)

2、TYPE-C USB数据线一根

3、SIM卡一张

4、Air780EHM/780EGH/780EHV核心板和数据线的硬件接线方式为

- Air780EHM核心板通过TYPE-C USB口供电；（核心板USB旁边的开关拨到on一端）

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## **演示软件环境**

1、Luatools下载调试工具： https://docs.openluat.com/air780epm/common/Luatools/

2、内核固件版本：
Air780EHM:https://docs.openluat.com/air780epm/luatos/firmware/version/
Air780EGH:https://docs.openluat.com/air780egh/luatos/firmware/version/
Air780EHV:https://docs.openluat.com/air780ehv/luatos/firmware/version/

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