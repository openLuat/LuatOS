--[[
demo说明:
1. 演示wifi联网操作
2. 演示长连接操作
3. 演示简易的网络状态灯
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"
--_G.httpv2 = require("httpv2")

log.info("main", "simple http demo")

-- //////////////////////////////////////////////////////////////////////////////////////
-- wifi 相关的代码
if wlan ~= nil then
    log.info("mac", wlan.get_mac())
    local ssid = "uiot"
    local password = "12345678"
    -- 方式1 直接连接, 简单快捷
    --wlan.connect(ssid, password) -- 直接连
    -- 方式2 先扫描,再连接. 例如根据rssi(信号强度)的不同, 择优选择ssid
    sys.taskInit(function()
        wlan.scan()
        sys.waitUntil("WLAN_SCAN_DONE", 30000)
        local re = wlan.scan_get_info()
        log.info("wlan", "scan done", #re)
        for i in ipairs(re) do
            log.info("wlan", "info", re[i].ssid, re[i].rssi)
        end
        log.info("wlan", "try connect to wifi")
        wlan.connect(ssid, password)
        sys.waitUntil("WLAN_READY", 15000)
        sys.wait(500)
        log.info("wifi", "self ip", socket.ip())
    end)
    -- 方法3 airkiss配网, 可参考 app/playit/main.lua
end

-- airkiss.auto(27) -- 预留的功能,未完成 
-- //////////////////////////////////////////////////////////////////////////////////////

--- 从这里开始, 代码与具体网络无关

-- 联网后自动同步时间
-- sys.subscribe("NET_READY", function ()
--     log.info("net", "!!! network ready event !!! send ntp")
--     sys.taskInit(function()
--         sys.wait(2000)
--         socket.ntpSync()
--     end)
-- end)

gpio.setup(21, 0)
_G.use_netled = 1 -- 启用1, 关闭0
sys.taskInit(function()
    while 1 do
        --log.info("wlan", "ready?", wlan.ready())
        if socket.isReady() then
            --log.info("netled", "net ready, slow")
            gpio.set(21, 1 * use_netled)
            sys.wait(1900)
            gpio.set(21, 0)
            sys.wait(100)
        else
            --log.info("netled", "net not ready, fast")
            gpio.set(21, 1 * use_netled)
            sys.wait(100)
            gpio.set(21, 0)
            sys.wait(100)
        end
    end
end)

sys.taskInit(function()
    -- 等待联网成功
    while true do
        while not socket.isReady() do 
            log.info("net", "wait for network ready")
            sys.waitUntil("NET_READY", 1000)
        end
        log.info("main", "http loop")
        sys.wait(1000)

        http.get("http://www.baidu.com/content-search.xml", {dw="/bd_search.xml"}, function(code,headers,body)
            log.info("http", "baidu", code, body) -- body和文件都有
        end)
        sys.wait(5000)
        http.get("https://mat1.gtimg.com/www/icon/favicon2.ico", {dw="/qq_log.ico"}, function(code, headers, body)
            log.info("http", "qq", code, body) -- 超过1500字节,只在文件里
        end)
        sys.wait(30000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
