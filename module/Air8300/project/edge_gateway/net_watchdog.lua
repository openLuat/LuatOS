--[[
@module  net_watchdog
@summary 网络环境检测看门狗功能模块
@version 1.1
@date    2026.09.10
@usage
本文件为网络环境检测看门狗功能模块，监控网络环境是否工作正常（设备和服务器双向通信正常，或者至少单向通信正常），核心业务逻辑为：
1、启动一个网络环境检测看门狗task，等待各网络业务功能模块来喂狗；喂狗超时后再兜底判定一次网络环境，
   如果默认网卡仍然持有IP，说明网络环境正常，则继续运行不重启；只有"网络环境异常且长时间无人喂狗"才控制软件重启；
2、喂狗超时时间取 10 分钟（给云端连接重试留足时间，避免"云暂时连不上->重启->更连不上"的雪崩循环）；
3、采用多源喂狗，以下任一情况都会重新计时（避免只看云端一个口子）：
   - AirCloud 等网络业务成功发送/收到数据时 sys.publish("FEED_NETWORK_WATCHDOG")；
   - 任一网卡（以太网/WiFi/4G）链路就绪或恢复时系统发布的 IP_READY。
4、喂狗超时且默认网卡无IP（socket.adapter(socket.dft()) 为 nil）时，等待3秒后软件重启。

本文件没有对外接口，直接在 main.lua 中 require "net_watchdog" 即可加载运行；
外部功能模块喂狗时，直接调用 sys.publish("FEED_NETWORK_WATCHDOG")
]]

-- 喂狗超时时间（毫秒）
local FEED_TIMEOUT = 10 * 60 * 1000 -- 10 分钟
-- 超时后等待重启时间（毫秒）
local REBOOT_DELAY = 3000           -- 3 秒

-- 附加喂狗事件清单：这些事件到达时统一转发为 FEED_NETWORK_WATCHDOG，重新计时
-- 1) IP_READY：任一网卡链路就绪或恢复（由系统/exnetif 发布）
-- 注意：本表不能包含 "FEED_NETWORK_WATCHDOG" 自身，否则会在订阅回调里自我转发形成死循环
local FORWARD_FEED_EVENTS = {
    "IP_READY",
}

-- 判断网络环境是否正常：默认网卡是否已获取到IP
-- @return boolean 是否正常, string IP地址（正常时）
local function net_env_is_ok()
    local ok, ip = pcall(socket.adapter, socket.dft())
    if ok and ip and ip ~= "" then
        return true, ip
    end
    return false, nil
end

-- 网络环境检测看门狗task处理函数
local function network_watchdog_task_func()
    while true do
        if sys.waitUntil("FEED_NETWORK_WATCHDOG", FEED_TIMEOUT) then
            -- 收到喂狗消息：业务活跃，继续下一轮计时
            log.debug("network_watchdog", "喂狗成功, 重新计时")
        else
            -- 喂狗超时：再兜底判定一次网络环境
            local net_ok, ip = net_env_is_ok()
            if net_ok then
                log.warn("network_watchdog", "喂狗超时, 但默认网卡仍有IP(" .. tostring(ip) .. "), 网络环境正常, 继续运行")
            else
                log.error("network_watchdog", "网络环境异常(默认网卡无IP)且喂狗超时, 准备重启")
                -- 等待3秒钟，然后软件重启
                sys.wait(REBOOT_DELAY)
                rtos.reboot()
            end
        end
    end
end

-- 订阅附加喂狗事件，统一转发为 FEED_NETWORK_WATCHDOG
for _, evt in ipairs(FORWARD_FEED_EVENTS) do
    sys.subscribe(evt, function()
        sys.publish("FEED_NETWORK_WATCHDOG")
    end)
end

-- 创建并启动一个task
sys.taskInit(network_watchdog_task_func)
