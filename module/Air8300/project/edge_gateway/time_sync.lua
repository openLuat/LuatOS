--[[
@module  time_sync
@summary NTP 时间同步模块
@version 1.0
@date    2026.09.09
@usage
本文件为 NTP 时间同步模块，负责等待网络就绪后执行网络授时，确保设备系统时间的准确性。
等待默认网卡连接成功后执行 socket.sntp() 授时，并等待 NTP_UPDATE 事件确认授时完成。

本文件没有对外接口，直接在 main.lua 中 require "time_sync" 即可加载运行。
]]

local net_config = require "net_config"

-- 时间同步任务处理函数
local function time_sync_task_func()
    -- 等待默认网卡连接成功（IP_READY）
    while not socket.adapter(socket.dft()) do
        log.warn("time_sync", "等待默认网卡就绪", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 读取 NTP 服务器配置
    local c = net_config.load()
    local ntp_server = c.ntp_server or "ntp.aliyun.com"

    -- 执行 NTP 授时
    log.info("time_sync", "开始 NTP 授时, 服务器:", ntp_server)
    socket.sntp(ntp_server)
    if sys.waitUntil("NTP_UPDATE", 10000) then
        log.info("time_sync", "NTP 授时成功")
    else
        log.warn("time_sync", "NTP 授时超时")
    end
end

-- 创建并启动时间同步任务
sys.taskInit(time_sync_task_func)
