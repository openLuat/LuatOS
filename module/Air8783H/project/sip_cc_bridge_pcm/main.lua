-- Air8000w 纯 PCM CC <-> SIP 桥接应用入口。
PROJECT = "SIP_CC_BRIDGE_PCM"
VERSION = "1.1.9"

log.info("main", PROJECT, VERSION)
    -- 初始化硬件看门狗（Air153C，config.WDT_CONFIG 控制是否启用）
local air153c_wdt = require("air153c_wdt")
if air153c_wdt and air153c_wdt.init then air153c_wdt.init() end

require "netdrv_device"
require "sip_cc_app"

sys.run()
