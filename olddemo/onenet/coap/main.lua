-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "onenetdemo"
VERSION = "1.0.0"

--[[
本demo演示的是 OneNet Studio, 注意区分
https://open.iot.10086.cn/studio/summary
https://open.iot.10086.cn/doc/v5/develop/detail/iot_platform

本demo演示的是coap方式
]]

-- sys库是标配
_G.sys = require("sys")

local onenetcoap = require("onenetcoap")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif rtos.bsp() == "AIR105" then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    elseif http then
        sys.waitUntil("IP_READY")
    else
        while 1 do
            sys.wait(1000)
            log.info("http", "当前固件未包含http库")
        end
    end
    log.info("已联网")
    sys.publish("net_ready")
end)



sys.taskInit(function()
    sys.waitUntil("net_ready")
    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 1000)
    -- 设备信息, 要按实际情况填
    local dev = {
        product_id = "SJaLt5cVL2",
        device_name = "luatospc",
        device_key = "dUZVVWRIcjVsV2pSbTJsckd0TmgyRXNnMTJWMXhIMkk=",
        debug = false
    }
    if onenetcoap.setup(dev) then
        onenetcoap.start()
    else
        log.error("配置失败")
    end
end)

sys.taskInit(function()
    sys.waitUntil("net_ready")
    while 1 do
        -- 模拟定时上行数据
        sys.wait(5000)
        local post = {
            id = "123",
            params = {
                WaterMeterState = {
                    value = 0
                }
            }
        }
        -- 这里走的是物模型
        onenetcoap.uplink("thing/property/post", post)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
