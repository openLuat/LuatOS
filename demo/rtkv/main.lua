
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rtkvdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require

详细说明请查阅文档 https://wiki.luatos.com/api/libs/rtkv.html
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

rtkv = require "rtkv"


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

if mcu and rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103" then
    mcu.setClk(240)
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
        LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
        log.info("wlan", json.encode(wlan.getInfo()), wlan.getIP())
    elseif rtos.bsp() == "AIR105" then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif rtos.bsp() == "EC618" then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        -- log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    end
    log.info("已联网")
    sys.publish("net_ready")
end)

sys.taskInit(function()
    sys.waitUntil("net_ready")
    sys.wait(100)
    rtkv.setup()
    adc.open(adc.CH_CPU)
    adc.open(adc.CH_VBAT)
    while 1 do
        -- 单传一个数据
        -- local ok = rtkv.set("vbat", adc.get(adc.CH_VBAT))
        -- ok = ok and rtkv.set("cputemp", adc.get(adc.CH_CPU))
        -- 批量传多个数据
        local data = {
            vbat = adc.get(adc.CH_VBAT),
            cputemp = adc.get(adc.CH_CPU),
            uptime = mcu.ticks(),
            bsp = rtos.bsp()
        }
        local total, used, max_used = rtos.meminfo()
        data["mem_lua_used"] = used
        data["mem_lua_max"] = max_used
        local total, used, max_used = rtos.meminfo("sys")
        data["mem_sys_used"] = used
        data["mem_sys_max"] = max_used
        data["local_ip"] = socket.localIP()
        local ok = rtkv.sets(data)
        log.info("rtkv", "上报结果", ok)
        sys.wait(15000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
