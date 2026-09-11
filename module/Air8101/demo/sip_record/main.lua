PROJECT = "air8101_sip_record"
VERSION = "001.000.000"

sys = require "sys"

local ok, config = pcall(require, "config")
if not ok or type(config) ~= "table" then
    log.error("sip_record", "缺少 config.lua，请复制 config.lua.template 并填写 Wi-Fi 和 SIP 参数")
else
    local netdrv_wifi = require "netdrv_wifi"
    if netdrv_wifi.start(config.wifi) then
        require("sip_record_app").start(config)
    end
end

sys.run()
