-- SIP -> CC 桥接期间自动发送网络 DTMF，使用模组内部 PCM，无需本地 Codec。
PROJECT = "SIP_CC_BRIDGE_DTMF"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)
assert(cc and type(cc.sendDtmf) == "function", "firmware missing cc.sendDtmf")
local air153c_wdt = require "air153c_wdt"
air153c_wdt.init()
require "netdrv_device"
require "sip_cc_app"
sys.run()
