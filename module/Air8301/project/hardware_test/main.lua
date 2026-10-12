--[[
@module  main
@summary Air8301_V0 硬件测试固件主入口
@version 1.0
@date    2026.08.04
@author  江访
@usage
本固件为 Air8301 硬件测试固件（基于 Air8000W 主控），测试功能包括：
1、4G/WiFi/以太网通信
2、双RS485/RS232通信
3、DI输入监测/DO继电器控制
4、蜂鸣器/状态灯/看门狗/SPI Flash
5、4.3寸ST6201触摸屏操作

=== 系统启动流程 ===

main.lua 只负责加载程序，不执行业务初始化：

  阶段1: require "app_main" → 板级初始化（GPIO 上电时序、外设供电）
  阶段2: require "ui_main"  → LCD/TP 驱动加载 + 窗口模块加载 + 硬件初始化协程
  阶段3: sys.run() → 事件循环

硬件初始化时序（在 ui_main.lua 的 init_ui_task 协程中执行）：
  LCD 硬件初始化 → AirUI 引擎 + 字体 → TP 触摸初始化 → 打开首页 → 背光开启
  对齐工厂引擎 app_engine 的 Engine_Air8301_4inch_480x272_000_V000 初始化时序
]]

--[[
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
-- main.lua - 程序入口文件

PROJECT = "Air8301_HardwareTest"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 窗口管理器（供各窗口模块使用，需在业务模块之前全局可见）
exwin = require "exwin"

-- 业务模块加载（板级初始化：GPIO 上电时序、外设供电）
require "app_main"

-- UI 页面模块加载（含 LCD/TP 驱动加载 + 硬件初始化协程）
require "ui_main"

-- 事件循环
sys.run()
