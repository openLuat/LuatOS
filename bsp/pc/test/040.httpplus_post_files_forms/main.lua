
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"
httpplus = require "httpplus"

sys.taskInit(function()
    sys.waitUntil("IP_READY")

    local opts = {url="http://httpbin.air32.cn/post", method="POST"}
    opts.headers = {ABC="1234"}
    opts.files = {file="/luadb/wifi.json"}
    opts.forms = {ttt="wendal"}
    -- opts.debug = true
    local code, resp = httpplus.request(opts)
    -- log.info("httpplus", code, json.encode(resp.headers), resp.body:query())
    log.info("httpplus", code, resp.body:query())
end)

sys.run()
