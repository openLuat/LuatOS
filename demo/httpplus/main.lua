
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要socket库, 大部分能联网的设备都具有这个库
socket是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
httpplus = require "httpplus"


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

function test_httpplus()
    sys.waitUntil("net_ready")
    -- 调试开关
    httpplus.debug = true

    -- socket.sslLog(3)
    -- local code, resp =httpplus.request({method="POST", url="https://abc:qq@whoami.k8s.air32.cn/goupupup"})
    -- log.info("http", code, resp)

    -- 预期返回302
    -- local code, resp = httpplus.request({method="POST", url="https://air32.cn/goupupup"})
    -- log.info("http", code, resp)

    -- local code, resp = httpplus.request({method="POST", url="https://httpbin.air32.cn/post", files={abcd="/luadb/libfastlz.a"}})
    -- log.info("http", code, resp)

    -- local code, resp = httpplus.request({method="POST", url="https://httpbin.air32.cn/anything", forms={abcd="12345"}})
    -- log.info("http", code, resp)

    -- local code, resp = httpplus.request({method="POST", url="https://httpbin.air32.cn/post", files={abcd="/luadb/abc.txt"}})
    -- log.info("http", code, resp)

    -- 简单GET请求
    local code, resp = httpplus.request({url="https://httpbin.air32.cn/"})
    log.info("http", code, resp)
    
    -- 简单POST请求
    -- local code, resp = httpplus.request({url="https://httpbin.air32.cn/post", body="123456", method="POST"})
    -- log.info("http", code, resp)
    
    -- 文件上传
    -- local code, resp = httpplus.request({url="https://httpbin.air32.cn/post", files={myfile="/luadb/abc.txt"}})
    -- log.info("http", code, resp)
    
    -- 自定义header的GET请求
    -- local code, resp = httpplus.request({url="https://httpbin.air32.cn/get", headers={Auth="12312234"}})
    -- log.info("http", code, resp)
    
    -- 带鉴权信息的GET请求
    -- local code, resp = httpplus.request({url="https://wendal:123@httpbin.air32.cn/get", headers={Auth="12312234"}})
    -- log.info("http", code, resp)
    
    -- PUT请求
    -- local code, resp = httpplus.request({url="https://httpbin.air32.cn/put", method="PUT", body="123"})
    -- log.info("http", code, resp)

    -- 表单POST
    -- local code, resp = httpplus.request({url="https://httpbin.air32.cn/post", forms={abc="123"}})
    -- log.info("http", code, resp)

    -- 响应体chucked编码测试
    local code, resp = httpplus.request({url="https://httpbin.air32.cn/stream/1"})
    log.info("http", code, resp)
    if code == 200 then
        log.info("http", "headers", json.encode(resp.headers))
        local body = resp.body:query()
        log.info("http", "body", body:toHex())
        log.info("http", "body", body)
        log.info("http", "body", json.decode(body:trim()))
        -- log.info("http", "body", json.decode(resp.body))
    end
end

sys.taskInit(test_httpplus)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
