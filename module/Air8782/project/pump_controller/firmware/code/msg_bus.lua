--[[
@module  msg_bus
@summary 模块间消息主题（TOPIC）常量定义
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
集中定义跨模块通信的消息主题常量，避免字符串散落。
本模块仅为常量，有对外接口，末尾 return M。
]]

local M = {}

-- 网络状态（netdrv_4g → excloud_app / collect_task / fota_app）
M.NET_READY      = "NET_READY"      -- 4G 网络就绪
M.NET_DISCONNECT = "NET_DISCONNECT" -- 网络断开

-- 采集数据（collect_task → aircloud_report）
M.PUMP_DATA_READY = "PUMP_DATA_READY" -- 一轮采集完成

-- AirCloud 服务（excloud_app → aircloud_report / oam_logger）
M.AIRCLOUD_READY = "AIRCLOUD_READY" -- 鉴权成功，云连接就绪
M.AIRCLOUD_CMD   = "AIRCLOUD_CMD"   -- 收到云平台下行命令
M.CTRL_RESULT    = "CTRL_RESULT"    -- 控制执行完成

-- 网络业务看门狗（其它模块 → network_watchdog）
M.FEED_NET_WDT = "FEED_NETWORK_WATCHDOG" -- 喂狗

return M
