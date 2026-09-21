--[[
@module  ntp_time
@summary NTP 时间同步（供上报时间戳使用）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md F-010（时间同步）：
网络就绪后触发一次 NTP 同步，等待 NTP_UPDATE 事件；同步成功后 os.time() 即为准确时间，
供 aircloud_report 填充 timestamp 使用。
本模块无对外接口，直接 require "ntp_time" 即加载运行。
]]

local msg_bus = require("msg_bus")

-- NTP 同步任务
local function ntp_task()
    -- 等待网络就绪
    sys.waitUntil(msg_bus.NET_READY)

    -- 触发 NTP 同步
    socket.sntp()
    if sys.waitUntil("NTP_UPDATE", 30000) then
        log.info("ntp_time", "NTP 时间同步完成", os.date("%Y-%m-%d %H:%M:%S"))
    else
        log.warn("ntp_time", "NTP 时间同步超时")
    end
end

sys.taskInit(ntp_task)
