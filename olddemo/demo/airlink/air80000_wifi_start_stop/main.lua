
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

-- 通过boot按键方便刷Air8000S
function PWR8000S(val)
    gpio.set(23, val)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

sys.subscribe("IP_READY", function(ip, id)
    log.info("ip_ready", ip, id)
end)

sys.subscribe("IP_LOSE", function(id)
    log.info("ip_lose", id)
end)

-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end)

sys.taskInit(function()

    while 1 do
        log.info("初始化wifi")
        wlan.init()
        log.info("尝试连接sta")
        wlan.connect("luatos1234", "12341234")
        sys.wait(15000)
        log.info("关闭wifi芯片")
        PWR8000S(0)
        sys.wait(10*1000) -- 等10秒
        log.info("打开wifi芯片， 然后等10秒")
        PWR8000S(1)
        sys.wait(10*1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
