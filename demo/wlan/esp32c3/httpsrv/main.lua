-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")


-- function meminfo()
--     log.info("lua", rtos.meminfo())
--     log.info("sys", rtos.meminfo("sys"))
-- end

-- 初始化LED灯, 开发板上左右2个led分别是gpio12/gpio13
local LEDA= gpio.setup(12, 0, gpio.PULLUP)
local LEDB= gpio.setup(13, 0, gpio.PULLUP)

sys.taskInit(function()
    sys.wait(1000)
    wlan.init()
    -- 修改成自己的ssid和password
    wlan.connect("myssid", "mypassword")
    -- wlan.connect("uiot", "")
    log.info("wlan", "wait for IP_READY")
    
    while not wlan.ready() do
        local ret, ip = sys.waitUntil("IP_READY", 30000)
        -- wlan连上之后, 这里会打印ip地址
        log.info("ip", ret, ip)
        if ip then
            _G.wlan_ip = ip
        end
    end
    log.info("wlan", "ready !!", wlan.getMac())
    sys.wait(1000)
    httpsrv.start(80, function(fd, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
        -- meminfo()
        if uri == "/led/1" then
            LEDA(1)
            return 200, {}, "ok"
        elseif uri == "/led/0" then
            LEDA(0)
            return 200, {}, "ok"
        end
        return 404, {}, "Not Found" .. uri
    end)
    log.info("web", "pls open url http://" .. _G.wlan_ip .. "/")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
