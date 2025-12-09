--[[
@module airkiss_task
@summary airkiss 配网功能模块
@version 1.0
@date    2025.12.8
@author  拓毅恒
@usage
用法实例

启动 AirKiss 配网功能
- 运行 airkiss_task 任务，先检查是否有已保存的配网信息
- 如有保存的信息则直接连接，否则启动airkiss配网
- 配网成功后将信息保存到fskv并重启设备

注：本demo无需额外配置，直接在 main.lua 中 require "airkiss_task" 即可加载运行。
]]

-- 订阅IP_READY事件，获取IP成功后触发
local function get_ip_ready(ip)
    log.info("wlan", "ip ready", ip)
    -- 联网成功, 可以发起http, mqtt, 等请求了
end
sys.subscribe("IP_READY", get_ip_ready)

-- 订阅SC_RESULT事件，配网成功后触发
local function on_airkiss_success(ssid, password)
    log.info("airkiss", "配网成功", ssid, password)
end
sys.subscribe("SC_RESULT", on_airkiss_success)

local function start_airkiss()
    -- 初始化fskv, 用于存储配网信息
    fskv.init()
    -- 初始化wifi协议栈
    wlan.init()

    -- 获取上次保存的配网信息, 如果存在就直接联网, 不需要配网了
    -- 注意, fskv保存的数据是掉电存储的, 刷脚本/刷固件也不会清除
    -- 如需完全清除配置信息, 可调用 fskv.clear() 全清
    if fskv.get("wlan_ssid") then
        wlan.connect(fskv.get("wlan_ssid"), fskv.get("wlan_passwd"))
        return
    end

    -- 配网时选用 AirKiss 模式
    -- 仅支持2.4G的wifi, 5G wifi是不支持的
    -- 配网时, 手机应靠近模块, 以便更快配网成功
    while true do
        log.info("wlan", "启动airkiss")
        wlan.smartconfig(wlan.AIRKISS)
        local ret, ssid, passwd = sys.waitUntil("SC_RESULT", 180*1000) -- 等3分钟
        if ret == false then
            log.info("smartconfig", "timeout")
            wlan.smartconfig(wlan.STOP)
            sys.wait(3000)
        else
            -- 获取配网后, ssid和passwd会有值
            log.info("smartconfig", ssid, passwd)
            -- 获取IP成功, 将配网信息存入fskv, 掉电也能保存
            log.info("fskv", "save ssid and passwd")
            fskv.set("wlan_ssid", ssid)
            fskv.set("wlan_passwd", passwd)

            -- 重启后将使用配网信息自动连接
            log.info("wifi", "wait 3s to reboot")
            sys.wait(3000)
            rtos.reboot()
            break
        end
    end

end

sys.taskInit(start_airkiss)