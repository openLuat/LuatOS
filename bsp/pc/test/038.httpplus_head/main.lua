
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"
httpplus = require "httpplus"

sys.taskInit(function()
    sys.waitUntil("IP_READY")

    local opts = {url="http://httpbin.air32.cn/get", method="GET"}
    opts.headers = {ABC="1234"}
    local code, resp = httpplus.request(opts)
    log.info("httpplus", code, json.encode(resp.headers), resp.body:query())
end)

sys.run()
