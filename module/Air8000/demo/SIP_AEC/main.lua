-- Air8000 + Air1103 UART PCM SIP，AEC由Air1103芯片处理。
PROJECT = "AIR8000_AIR1103_SIP_AEC"
VERSION = "001.000.000"

sys = require "sys"
sysplus = require "sysplus"

log.info("main", PROJECT, VERSION, rtos.version())
require "netdrv_device"
require "sip_app_main"
require "sip_app_key"

sys.run()
