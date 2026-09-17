-- Air8000w 纯 PCM CC <-> SIP 桥接应用入口。
PROJECT = "SIP_CC_BRIDGE_PCM"
VERSION = "1.0.0"
require "sys"
require "sysplus"
log.info("main", PROJECT, VERSION)
require "netdrv_device"
require "sip_cc_app"
sys.run()
