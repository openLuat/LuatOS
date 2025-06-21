-- @module airkiss
-- @release 2025.05.27
-- 运行环境：本demo可直接在Air8101开发板上运行。
-- 执行逻辑：先执行airkiss配网，获取IP成功后, 将配网信息存入fskv，重启后自动连接。

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "AirKiss"
VERSION = "1.0.0"

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.subscribe("IP_READY", function(ip)
    log.info("wlan", "ip ready", ip)
    -- 联网成功, 可以发起http, mqtt, 等请求了
end)

sys.subscribe("SC_RESULT", function(ssid, password)
    log.info("why", ssid, password)
end)

fskv.init()  -- 初始化fskv, 用于存储配网信息

local function start_airkiss()
    sys.wait(500) -- 这里等500ms只是方便看日志,非必须
    wlan.init() -- 初始化wifi协议栈

    -- 获取上次保存的配网信息, 如果存在就直接联网, 不需要配网了
    -- 注意, fskv保存的数据是掉电存储的, 刷脚本/刷固件也不会清除
    -- 如需完全清除配置信息, 可调用 fskv.clear() 全清
    if fskv.get("wlan_ssid") then
        wlan.connect(fskv.get("wlan_ssid"), fskv.get("wlan_passwd"))
        return -- 等联网就行了
    end

    -- 以下是smartconfig之 AirKiss 配网
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
            sys.wait(3000) -- 再等3s重新配网, 或者直接reboot也行
        else
            -- 获取配网后, ssid和passwd会有值
            log.info("smartconfig", ssid, passwd)
            -- 获取IP成功, 将配网信息存入fskv, 做持久化存储
            log.info("fskv", "save ssid and passwd")
            fskv.set("wlan_ssid", ssid)
            fskv.set("wlan_passwd", passwd)

            -- -- 这里建议重启, 当然这也不是强制的
            log.info("wifi", "wait 3s to reboot")
            sys.wait(3000)
            -- -- 重启后有配网信息, 所以就自动连接
            rtos.reboot()
            break
        end
    end

end

sys.taskInit(start_airkiss) -- 启动配网任务

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
