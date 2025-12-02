
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    local code, headers, body = http.request("GET", "https://httpbin.air32.cn/get").wait()
    log.info("http", code, json.encode(headers), body)
    -- local code, headers, body = http.request("POST", "http://ql.betterforyou.com.cn:9090/ck/app/appUpgrade/findMiniUpgrade?equId=QL10000001&equType=1").wait()
    -- log.info("http.get", code, headers, body)

    log.info("GoGoGo")
    sys.wait(1000)
    
    local body = io.readFile("/luadb/wifi.json")
    local code, headers, body = http.request("POST", "http://wifi.air32.cn/wifi", nil, body).wait()
    log.info("http", code, json.encode(headers), #body)
    -- log.info("http", "body", #body)
    -- log.info("http", "body", body)

    socket.sslLog(5)
    local httpplus = require "httpplus"
    -- local code, resp = httpplus.request({url="https://vaviri-back-ph4lj.ondigitalocean.app/state"})
    local code, resp = httpplus.request({
        url="http://wifi.air32.cn/wifi", 
        body=io.readFile("/luadb/wifi.json"), 
        headers={"Content-Type", "application/json"}, 
        method="POST"}
    )
    local body = resp.body:query()
    -- log.info("http", code, json.encode(resp.headers), #body)
    log.info("http2", "body", #body)
    log.info("http2", "body", body)
    log.info("http2", "body", body:toHex())

    -- body = io.readFile("/luadb/gzip")
    -- log.info("gzip", #body)
    -- -- log.info("http", miniz.uncompress(body:sub(11)))
    -- log.info("http", miniz.uncompress(body:sub(11), 0))
    -- log.info("http", body:toHex())

    local code, headers, body = http.request("GET", "http://httpbin.air32.cn/range/1024", nil, nil, {debug=false}).wait()
    log.info("http3", code, json.encode(headers), body)

    local code, headers = http.request("GET", "http://httpbin.air32.cn/stream-bytes/20", nil, nil, {debug=true}).wait()
    log.info("http4", code, headers, body)
end)

sys.run()
