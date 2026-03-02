## 功能模块介绍

1、main.lua：主程序入口，负责初始化系统环境；

2、log_test.lua：日志功能测试模块，演示Air8101的日志输出功能；

## 演示功能概述

1、log_test：日志输出等级测试

默认日志输出等级为 DEBUG，即输出 debug 及以上级别的日志；

log.setLevel("INFO")： 输出 info 及以上级别的日志；

log.setLevel("WARN")： 输出 warn 及以上级别的日志；

log.setLevel("ERROR")： 输出 error 级别的日志；

log.setLevel("SILENT")： 静默所有日志，即禁止日志有任何内容输出；

## 演示硬件环境

1、Air1601开发板一个：

2、TYPE-C USB数据线一根

3、Air1601开发板和数据线的硬件接线方式为

- Air1601开发板通过TYPE-C USB口供电；

- 如果测试提示“ramrun下载失败，串口异常导致握手失败”，可能是供电不足，此时再通过直流稳压电源对开发板的VIN管脚进行5V供电；

- TYPE-C USB数据线直接插到核心板的TYPE-C USB座子，另外一端连接电脑USB口；

## 演示软件环境

1、[Luatools下载调试工具](https://docs.openluat.com/air780epm/common/Luatools/)

2、[Air1601 最新固件](https://gitee.com/openLuat/LuatOS/releases/tag/v1004.air1601.release)

## 演示核心步骤

1、搭建好硬件环境

2、Luatools烧录内核固件和demo脚本代码

3、烧录成功后，自动开机运行，通过luatools日志可以观察到以下信息：

``` lua
[2026-03-02 10:53:48.510][LTOS/N][000000000.013]:I/user.main project name is  logdemo version is  001.000.000
[2026-03-02 10:53:48.510][LTOS/N][000000000.015]:日志功能测试开始
[2026-03-02 10:53:48.515][LTOS/N][000000000.016]:默认日志级别: 1
[2026-03-02 10:53:48.515][LTOS/N][000000000.016]:测试日志级别: 1
[2026-03-02 10:53:48.520][LTOS/N][000000000.016]:D/user.logdemo debug message
[2026-03-02 10:53:48.520][LTOS/N][000000000.016]:I/user.logdemo info message
[2026-03-02 10:53:48.526][LTOS/N][000000000.016]:W/user.logdemo warn message
[2026-03-02 10:53:48.526][LTOS/N][000000000.016]:E/user.logdemo error message
[2026-03-02 10:53:48.531][LTOS/N][000000000.016]:测试日志级别: INFO
[2026-03-02 10:53:48.531][LTOS/N][000000000.016]:I/user.logdemo info message
[2026-03-02 10:53:48.531][LTOS/N][000000000.016]:W/user.logdemo warn message
[2026-03-02 10:53:48.536][LTOS/N][000000000.016]:E/user.logdemo error message
[2026-03-02 10:53:48.536][LTOS/N][000000000.016]:测试日志级别: WARN
[2026-03-02 10:53:48.541][LTOS/N][000000000.017]:W/user.logdemo warn message
[2026-03-02 10:53:48.546][LTOS/N][000000000.017]:E/user.logdemo error message
[2026-03-02 10:53:48.546][LTOS/N][000000000.017]:测试日志级别: ERROR
[2026-03-02 10:53:48.546][LTOS/N][000000000.017]:E/user.logdemo error message
[2026-03-02 10:53:48.552][LTOS/N][000000000.017]:测试日志级别: SILENT
[2026-03-02 10:53:48.557][LTOS/N][000000000.017]:恢复默认日志输出等级: 1
[2026-03-02 10:53:48.562][LTOS/N][000000000.017]:I/user.logdemo 数值: 123 布尔值: true 表: table: 1C27EDF0
```
