-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

--[[
本demo演示AP的配网实例
1. 启动后, 会创建一个 luatos_ + mac地址的热点
2. 热点密码是 12341234
3. 热点网关是 192.168.4.1, 同时也是配网网页的ip
4. http://192.168.4.1
]]


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 初始化LED灯, 开发板上左右2个led分别是gpio12/gpio13
local LEDA= gpio.setup(12, 0, gpio.PULLUP)
-- local LEDB= gpio.setup(13, 0, gpio.PULLUP)

local scan_result = {}

sys.taskInit(function()
    sys.wait(1000)
    wlan.init()
    sys.wait(300)
    -- AP的ssid和password
    wlan.createAP("luatos_" .. wlan.getMac(), "12341234")
    log.info("AP", "luatos_" .. wlan.getMac(), "12341234")
    sys.wait(500)
    wlan.scan()
    -- sys.wait(500)
    httpsrv.start(80, function(fd, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
        -- /led是控制灯的API
        if uri == "/led/1" then
            LEDA(1)
            return 200, {}, "ok"
        elseif uri == "/led/0" then
            LEDA(0)
            return 200, {}, "ok"
        -- 扫描AP
        elseif uri == "/scan/go" then
            wlan.scan()
            return 200, {}, "ok"
        -- 前端获取AP列表
        elseif uri == "/scan/list" then
            return 200, {["Content-Type"]="applaction/json"}, (json.encode({data=_G.scan_result, ok=true}))
        -- 前端填好了ssid和密码, 那就连接吧
        elseif uri == "/connect" then
            if method == "POST" and body and #body > 2 then
                local jdata = json.decode(body)
                if jdata and jdata.ssid then
                    -- 开启一个定时器联网, 否则这个情况可能会联网完成后才执行完
                    sys.timerStart(wlan.connect, 500, jdata.ssid, jdata.passwd)
                    return 200, {}, "ok"
                end
            end
            return 400, {}, "ok"
        -- 根据ip地址来判断是否已经连接成功
        elseif uri == "/connok" then
            return 200, {["Content-Type"]="applaction/json"}, json.encode({ip=socket.localIP()})
        end
        -- 其他情况就是找不到了
        return 404, {}, "Not Found" .. uri
    end)
    log.info("web", "pls open url http://192.168.4.1/")
end)

-- wifi扫描成功后, 会有WLAN_SCAN_DONE消息, 读取即可
sys.subscribe("WLAN_SCAN_DONE", function ()
    local result = wlan.scanResult()
    _G.scan_result = {}
    for k,v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(_G.scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(_G.scan_result))
end)

sys.subscribe("IP_READY", function()
    -- 联网成功后, 模拟上报到服务器
    log.info("wlan", "已联网", "通知服务器")
    sys.taskInit(function()
        sys.wait(1000)
        -- 以下是rtkv库的模拟实现, 这里就不强制引入rtkv了
        local token = mcu.unique_id():toHex()
        local device = wlan.getMac()
        local params = "device=" .. device .. "&token=" .. token
        params = params .. "&key=ip&value=" .. (socket.localIP())
        local code = http.request("GET", "http://rtkv.air32.cn/api/rtkv/set?" .. params, {timeout=3000}).wait()
        log.info("上报结果", code)
    end)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
