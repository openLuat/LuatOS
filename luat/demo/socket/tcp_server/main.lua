
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "tcpserver"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")


srv = require("tcpsrv")


-- 因为这是通用demo, air101/air103跑满速才不至于太慢-_-
if mcu then
    mcu.setClk(240)
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
        -- wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
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
    sys.waitUntil("net_ready")
    log.info("联网完成", "准备启动tcp server")
    sys.wait(1000)
    SerDemo(80)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
