-- SIP <-> CC 双向 DTMF（INFO / RFC4733），使用内部 PCM，无需本地 Codec。
PROJECT = "SIP_CC_BRIDGE_DTMF"
VERSION = "1.1.0"

log.info("main", PROJECT, VERSION)
assert(cc and type(cc.sendDtmf) == "function", "firmware missing cc.sendDtmf")
local air153c_wdt = require "air153c_wdt"
air153c_wdt.init()
require "netdrv_device"
require "sip_cc_app"
sys.run()
