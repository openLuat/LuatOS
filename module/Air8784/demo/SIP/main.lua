--[[
@module  main
@summary Air8784 + 1103 SIP 双向通话 Demo
@version 1.0
@date    2026.09.16
@description
网络入口为 netdrv_device.lua，音频入口为 audio_drv.lua。
SIP 与按键业务分别由 sip_app_main 和 sip_app_key 加载。
烧录前请在 config.lua 中确认账号、音频和按键配置。
]]

PROJECT = "AIR8784_1103_AP_SIP"
VERSION = "001.000.001"

-- ==================== 启动信息与固件检查 ====================

log.info("main", PROJECT, VERSION, rtos.version())
assert(crypto and type(crypto.checksum) == "function", "Native crypto.checksum is required for 1103 SIP")


-- ==================== 网络驱动 ====================

require "netdrv_device"

-- ==================== SIP 与按键业务 ====================

require "sip_app_main"
require "sip_app_key"

-- 调试：确认 SIP 账号(由 hmeta.devid() 转十进制得到)，注册失败时对照合宙控制台
local cfg = require "config"
log.info("main", "SIP_USER", cfg.sip.sip_username, "DIAL", cfg.dial_number)

-- ==================== 程序入口 ====================

sys.run()
-- sys.run() 之后不要添加任何语句
