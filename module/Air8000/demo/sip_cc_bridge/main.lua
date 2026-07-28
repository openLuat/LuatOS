--[[
@module  main
@summary SIP/CC 音频桥接应用入口
@version 1.2
@date    2026.07.27
@usage
业务配置见 config.lua，通话流程见 sip_cc_app.lua。
]]

PROJECT = "sip_cc_bridge_demo"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

-- 实际项目建议启用异常信息存储和上传。
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 加载网络驱动和应用业务。
require "netdrv_device"
require "sip_cc_app"

-- 用户代码已结束。
sys.run()
-- sys.run()之后不要添加任何语句。
