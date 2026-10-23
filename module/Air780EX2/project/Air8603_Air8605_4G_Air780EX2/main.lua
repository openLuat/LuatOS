--[[
@module  main
@summary Air8603 / Air8605 开发板上 Air780EX2 的默认出厂固件入口
@version 1.0
@date    2026.10.23
@usage
本工程由 Air780ER2_Air780ER3 项目的 rndis_airlink 精简而来，只保留两部分业务功能：
1. CH390H 以太网 LAN 口（lan_ch390）
2. AirLink UART 4G 网络桥接（airlink_uart_4g）
另外保留网络指示灯（GPIO25 开机常亮）和 FOTA 远程升级。

硬件连接（沿用原工程配置，需按 Air8603 / Air8605 实际原理图确认）：
- CH390H  ：SPI0，CS=GPIO8，LAN_EN=GPIO27，INT=GPIO22
- AirLink ：UART1，2Mbps
- 网络指示灯：GPIO25，高电平点亮、低电平熄灭

注意：GPIO27 已作为 CH390H 的 LAN_EN，因此不再启用 AirLink 的 exairlinkwdt 看门狗。
]]
_G.PROJECT = "Air8603_Air8605_4G_Air780EX2"
_G.VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", _G.PROJECT, _G.VERSION)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 网络指示灯：GPIO25，开机常亮
log.info("main", "加载 NETLIGHT 项目配置")
require("netlight")

-- FOTA 远程升级
log.info("main", "加载 FOTA 项目配置")
require("fota3")

-- AirLink UART 4G 网络桥接
log.info("main", "加载 AIRLINK_UART 项目配置")
require("airlink_uart_4g")

-- CH390H 以太网 LAN 口
log.info("main", "加载 LAN_CH390 项目配置")
require("lan_ch390")


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
