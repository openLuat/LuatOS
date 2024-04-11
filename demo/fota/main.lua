
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fotademo"
VERSION = "1.0.0"

--[[
本demo 适用于 Air780E/Air780EG/Air600E
1. 需要 V1103及以上的固件
2. 需要 LuaTools 2.1.89 及以上的升级文件生成
]]

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "1234" -- 到 iot.openluat.com 创建项目,获取正确的项目id

sys = require "sys"
libfota = require "libfota"

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

-- 统一联网函数
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持, 要根据实际情况修改ssid和password!!
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- EC618系列, 如Air780E/Air600E/Air700E
        -- mobile.simid(2) -- 自动切换SIM卡, 按需启用
        -- 模块默认会自动联网, 无需额外的操作
    elseif w5500 then
        -- w5500 以太网
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
    elseif socket then
        -- 适配了socket库也OK, 就当1秒联网吧
        sys.timerStart(sys.publish, 1000, "IP_READY")
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("fota", "version", VERSION)
    end
end)


function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

-- 使用合宙iot平台进行升级
sys.taskInit(function()
    sys.waitUntil("net_ready")
    libfota.request(fota_cb)
end)
sys.timerLoopStart(libfota.request, 3600000, fota_cb)

-- 使用自建服务器进行升级
-- local ota_url = "http://192.168.1.5:8000/demo.fota"
-- local ota_url = "http://192.168.1.5:8000/demo.fota"
-- sys.taskInit(function()
--     sys.waitUntil("net_ready")
--     sys.wait(3000)
--     libfota.request(fota_cb, ota_url)
--     -- 按键触发
--     -- sys.wait(1000)
--     -- gpio.setup(0, function()
--     --     log.info("sayhi")
--     -- end, gpio.PULLUP)
-- end)
-- sys.timerLoopStart(libfota.request, 3600000, fota_cb, ota_url)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
