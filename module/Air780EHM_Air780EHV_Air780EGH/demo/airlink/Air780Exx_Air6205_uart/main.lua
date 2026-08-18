--[[
@module  main
@summary 780EXX + Air6205 WiFi联网演示入口（UART模式）
@version 1.0
@date    2026.07.07
@usage
演示功能概述
1.1 WiFi联网功能概述
本demo演示基于780EXX核心板 + Air6205 WiFi核心板，通过airlink UART协议实现WiFi联网功能。
1.2 系统工作原理
设备启动后，通过UART2连接Air6205，Air6205连接路由器WiFi热点后，780EXX即可通过airlink协议使用WiFi网络。
1.3 核心功能特性
- WiFi STA联网测试：780EXX通过airlink UART协议驱动Air6205连接WiFi热点，验证STA模式联网
- WiFi AP功能测试：STA连接成功后开启AP热点（名称: test, 密码: 12345678），验证Air6205的AP模式
- HTTP请求：联网成功后定时发送HTTP GET请求验证网络连通性
- 状态监控：实时监控airlink连接状态和网卡状态
1.4 接线说明（Air780EXX核心板 → Air6205核心板）
   28/U2RXD        → U1_TX
   29/U2TXD        → U1_RX
   VBAT            → VBAT
   GND             → GND

本示例基于合宙 Air780EXX + Air6205 模组，演示 780EXX 通过 airlink UART 协议驱动 Air6205 连接 WiFi 的完整实现流程。
更多说明参考本目录下的readme.md文件

注意事项：
1. 本demo使用UART2作为airlink通信串口（默认pin28/pin29），波特率2Mbps
2. 如需修改连接的WiFi热点，请修改network_airlink.lua中的SSID和密码参数
3. Air6205仅支持2.4G WiFi，不支持5G WiFi
]]
--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
PROJECT = "Air780EHM_Air6205_airlink_wifi"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 加载功能模块
require "network_airlink"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
