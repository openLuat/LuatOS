PROJECT = "sip_record_demo"
VERSION = "001.000.000"

sys = require "sys"

require "netdrv_4g"

local ok, config = pcall(require, "config")
if not ok or type(config) ~= "table" then
    log.error("sip_record", "缺少 config.lua，请复制 config.lua.template 并填写 SIP 账号")
else
    require("sip_record_app").start(config)
end

sys.run()
