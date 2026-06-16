--[[
@module  main
@summary RFA USB虚拟串口AT服务器示例
@version 1.0.0
@date    2026.06.15
@usage
本demo演示的核心功能为：
1. 在 Air780EHM 的 USB 虚拟串口 VUART_0 上启动 RFA (Radio Factory Agent)
2. 通过 PC 端串口调试工具手动发送 AT 指令
3. rfa.lua 解析 AT 协议并通过 mobile.rfTest* 与底层交互
4. 将 AT 响应通过 VUART_0 返回给 PC

硬件要求:
- Air780EHM / Air780EHV / Air780EGH 等支持 USB 虚拟串口的模组
- 固件必须打开 LUAT_USE_MOBILE_RFA 宏

使用步骤:
1. 用 Luatools 烧录本脚本 + 对应 firmware
2. 用 USB 线连接模组到 PC
3. 在设备管理器找到 USB 虚拟串口（通常是 AT 口或 DIAG 口）
4. 打开串口调试工具，波特率 115200
5. 手动发送 AT 指令，例如：
   AT
   ATE0
   AT+CGSN
   AT+CFUN=0
   AT+ECRFNST=02040900010003000500080022002600270028002900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000034126000076A
]]

PROJECT = "rfa_vuart_at_server"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 避免 Luatools 静态依赖扫描对链式调用解析失败
local rfa = require("rfa")

-- 启动 RFA AT 服务器，绑定到 USB 虚拟串口 VUART_0
-- 波特率对虚拟串口无实际意义，但保持 115200 与产线工具一致
rfa.start(uart.VUART_0, 115200)
log.info("rfa", "RFA AT server started on VUART_0")

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
