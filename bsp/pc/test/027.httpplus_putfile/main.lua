
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

_G.sys = require("sys")
require "sysplus"
httpplus = require "httpplus"

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    log.info("start", mcu.ticks())
    local opts = {url="http://upload.air32.cn/api/upload/jpg", method="POST", bodyfile="/luadb/test.jpg"}
    opts.headers = {ABC="1234"}
    local code, resp = httpplus.request(opts)
    log.info("httpplus", code, resp.body:query())
    log.info("done", mcu.ticks())
end)

sys.run()
