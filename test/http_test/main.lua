
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "uiot"
        local password = "12345678"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif mobile and mobile.imei then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    elseif w5500 then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    end

    -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    if crypto.cipher_suites then
        log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    end

    -------------------------------------
    -------- HTTP 演示代码 --------------
    -------------------------------------

    

    while 1 do
        -- 最普通的Http GET请求
        local code, headers, body = http.request("GET", "https://www.air32.cn/").wait()
        log.info("http.get", "air32.cn", code)
        sys.wait(100)

        -- ipv6测试, 仅EC618系列支持
        local code, headers, body = http.request("GET", "https://mirrors6.tuna.tsinghua.edu.cn/", nil, nil, {ipv6=true}).wait()
        log.info("http.get", "ipv6", code, json.encode(headers or {}), body and #body or 0)
        sys.wait(100)

        -- 一个比较特别的外网URL, 获取地震信息的
        local url ="https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"
        local code, headers, body = http.request("GET", url).wait()
        log.info("http.get", "earthquakes", code, json.encode(headers or {}), body and #body or 0)
        sys.wait(100)

        -- 超长URL测试
        local url ="https://www.baidu.com/?fdasfaisdolfjadklsjfklasdjflka=fdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflkafdasfaisdolfjadklsjfklasdjflka"
        local code, headers, body = http.request("GET", url).wait()
        log.info("http.get", "longurl", code, json.encode(headers or {}), body and #body or 0)
        sys.wait(100)

        -- 阿里云自动注册设备的验证, 不一样是200
        local url ="https://iot-auth.cn-shanghai.aliyuncs.com/auth/register/device"
        local req_headers = {}
        req_headers["Content-Type"] = "application/x-www-form-urlencoded"
        local req_body = "productKey=he1iZrw123&deviceName=861551056136351&random=2717&sign=DD31BA6E9E087A6DD88E96FD47A7AAA3&signMethod=HmacMD5"
        -- req_headers["Content-Length"] = tostring(#req_body)
        local code, headers, body = http.request("POST", url, req_headers, req_body).wait()
        log.info("http.get", "aliyun", code, json.encode(headers or {}), body and #body or 0)
        sys.wait(100)

        -- Content-Length:0的情况
        local code, headers, body = http.request("GET", "http://air32.cn/test/zero.txt").wait()
        log.info("http.get", "emtry content", code, json.encode(headers or {}), body and #body or 0)
        sys.wait(100)

        sys.wait(600000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
