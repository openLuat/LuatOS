-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

--[[
本demo需要 V100x系列固件, 不兼容V000x系列
https://gitee.com/openLuat/LuatOS/releases
]]

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

sys.subscribe("IP_READY", function(ip)
    log.info("wlan", "ip ready", ip)
    -- 联网成功, 可以发起http, mqtt, 等请求了
end)

fdb.kvdb_init()

-- 把BOOT键, 即GPIO9, 作为清除配网信息的按钮
BTN_BOOT = 9
gpio.debounce(BTN_BOOT, 1000)
gpio.setup(BTN_BOOT, function()
    log.info("gpio", "boot button pressed")
    sys.publish("BTN_BOOT")
end)

sys.taskInit(function()
    sys.wait(500) -- 这里等500ms只是方便看日志,非必须
    wlan.init() -- 初始化wifi协议栈

    -- 获取上次保存的配网信息, 如果存在就直接联网, 不需要配网了
    -- 注意, fdb保存的数据是掉电存储的, 刷脚本/刷固件也不会清除
    -- 如需完全清除配置信息, 可调用 fdb.clear() 全清
    if fdb.kv_get("wlan_ssid") then
       wlan.connect(fdb.kv_get("wlan_ssid"), fdb.kv_get("wlan_passwd"))
       return -- 等联网就行了
    end

    -- 以下是smartconfig之 esptouch 配网
    -- 配网APP请搜索 esptouch , 当前最新版2.3.0
    -- 配网时选用 esptouch, 虽然esptouch V2也是支持的,但 esptouch兼容性比较好
    -- ESP32C3仅支持2.4G的wifi, 5G wifi是不支持的
    -- 配网时, 手机应靠近模块, 以便更快配网成功
    while 1 do
        -- 启动配网, 默认是esptouch模式
        wlan.smartconfig()
        local ret, ssid, passwd = sys.waitUntil("SC_RESULT", 180*1000) -- 等3分钟
        if ret == false then
            log.info("smartconfig", "timeout")
            wlan.smartconfig(wlan.STOP)
            sys.wait(3000) -- 再等3s重新配网, 或者直接reboot也行
        else
            -- 获取配网后, ssid和passwd会有值
            log.info("smartconfig", ssid, passwd)
            -- 值得注意的是, 存在ssid和passwd填错的情况, 这里按获取到IP来算成功
            local ret = sys.waitUntil("IP_READY", 30000)
            if ret then
                -- 获取IP成功, 将配网信息存入fdb, 做持久化存储
                log.info("fdb", "save ssid and passwd")
                fdb.kv_set("wlan_ssid", ssid)
                fdb.kv_set("wlan_passwd", passwd)
                -- 等3秒再重启, 因为esptouch联网后会发生广播, 告知APP配网成功
                log.info("wifi", "wait 3s to reboot")
                sys.wait(3000)
                -- 这里建议重启, 当然这也不是强制的
                -- 重启后有配网信息, 所以就自动连接
                rtos.reboot()
            end
        end
    end
end)


-- 下面的task是演示通过按键清除配网信息
-- 实现的效果是: 开机500ms后, 长按BOOT按钮3秒以上, 清除配网信息, 然后重启或者快速闪灯.
sys.taskInit(function()
    -- 开机后, 先等500ms
    sys.wait(500)
    -- 然后开始监听BTN按钮
    while true do
        local flag = true
        while true do
            -- 等待boot按钮按下
            local ret = sys.waitUntil("BTN_BOOT", 3000)
            --log.info("gpio", "BTN_BOOT", "wait", ret)
            if ret then
                break
            end
        end
        log.info("wifi", "Got BOOT button pressed")
        for i=1, 30 do
            -- 要求持续3s的低电平, 若中途松开了,就无效咯
            if gpio.get(BTN_BOOT) ~= 0 then
                log.info("wifi", "BOOT button released, wait next press")
                flag = false
                break
            end
            sys.wait(100)
        end

        if flag then
            -- 用户的确要请求配网信息, 那就清除吧
            log.info("gpio", "boot pressed 3s, remove ssid/passwd")
            fdb.kv_del("wlan_ssid")
            fdb.kv_del("wlan_passwd")
            -- fdb.clear() -- 这里还有一个方案是清除fdb里的全部数据,从业务上说相当于恢复出厂配置
            log.info("gpio", "removed, wait for reboot")

            -- 方案1, 直接重启, 重启后因为没有配网数据了, 就自动开始配网
            -- rtos.reboot()

            -- 方案2, 100ms闪灯, 让用户自行复位重启
            gpio.setup(12, 0)
            while 1 do
                gpio.toggle(12)
                sys.wait(100)
            end
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
